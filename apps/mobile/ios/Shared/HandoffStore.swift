import Foundation
import CryptoKit
import Darwin

/// Shared only by Runner + ShareExtension. This is NOT the approved capture DB.
/// The caller must obtain explicit handoff-copy consent before append.
enum HandoffFailure: Error { case approvalRequired, unavailable, invalidInput, full, damaged }
struct HandoffRecord: Codable, Sendable {
  let id: String
  let name: String
  let format: String
  let bytes: Data
  let sha256: String
  let consentTS: Int64 // Device handoff consent, NOT library import/publication time.

  init(name: String, format: String, bytes: Data, consentTS: Int64 = Int64(Date().timeIntervalSince1970)) throws {
    self.id = UUID().uuidString.lowercased()
    self.name = String(String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })).prefix(120))
    self.format = format
    self.bytes = bytes
    self.sha256 = Self.digest(bytes)
    self.consentTS = consentTS
    try validate()
  }
  static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
  func validate() throws {
    guard HandoffStore.uuid(id), ["text", "markdown", "html", "pdf"].contains(format),
      !bytes.isEmpty, bytes.count <= (format == "pdf" ? 10 : 2) * 1024 * 1024,
      sha256 == Self.digest(bytes), name.count <= 120,
      consentTS >= 0, consentTS <= 253402300799,
      name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
      format == "pdf" || String(data: bytes, encoding: .utf8) != nil else { throw HandoffFailure.invalidInput }
  }
}
struct HandoffBatch: Codable { let version: Int; let records: [HandoffRecord] }
struct HandoffEntry {
  let id: String
  let record: HandoffRecord?
  let error: String?
}

final class HandoffStore {
  static let group = Bundle.main.object(forInfoDictionaryKey: "RefractAppGroup") as? String ?? "group.dev.refract"
  static let maxCount = 16
  static let maxBytes = 24 * 1024 * 1024
  private let root: URL
  init(root: URL) { self.root = root }
  static func appGroup() throws -> HandoffStore {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw HandoffFailure.unavailable }
    return HandoffStore(root: container.appendingPathComponent("share-handoff-v1", isDirectory: true))
  }
  static func uuid(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString.lowercased() == id }
  private func locked<T>(_ action: () throws -> T) throws -> T {
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    #if os(iOS)
    try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    var directory = root; try directory.setResourceValues(values)
    #endif
    let fd = open(root.appendingPathComponent(".lock").path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw HandoffFailure.unavailable }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw HandoffFailure.unavailable }
    defer { flock(fd, LOCK_UN) }
    // Only our interrupted atomic-write files, under the global process lock.
    // Published batches never expire or get swept.
    for file in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
      let name = file.lastPathComponent
      if name.hasPrefix(".pending-"), Self.uuid(String(name.dropFirst(9))) { try fm.removeItem(at: file) }
    }
    return try action()
  }
  private func files() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "json" && Self.uuid($0.deletingPathExtension().lastPathComponent) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
  private func read(_ file: URL) throws -> HandoffBatch {
    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= 40 * 1024 * 1024 else { throw HandoffFailure.damaged }
    let batch = try JSONDecoder().decode(HandoffBatch.self, from: Data(contentsOf: file))
    guard batch.version == 1, !batch.records.isEmpty, batch.records.count <= Self.maxCount,
      batch.records.reduce(0, { $0 + $1.bytes.count }) <= Self.maxBytes,
      Set(batch.records.map { $0.id }).count == batch.records.count else { throw HandoffFailure.damaged }
    for record in batch.records { try record.validate() }
    return batch
  }
  private func atomicWrite(_ batch: HandoffBatch, to destination: URL) throws {
    let data = try JSONEncoder().encode(batch)
    guard data.count <= 40 * 1024 * 1024 else { throw HandoffFailure.full }
    let temporary = root.appendingPathComponent(".pending-" + UUID().uuidString.lowercased())
    let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw HandoffFailure.unavailable }
    defer { close(fd); try? FileManager.default.removeItem(at: temporary) }
    #if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: temporary.path)
    #endif
    try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw HandoffFailure.unavailable }
        offset += count
      }
    }
    guard fsync(fd) == 0, rename(temporary.path, destination.path) == 0 else { throw HandoffFailure.unavailable }
    let directory = open(root.path, O_RDONLY)
    guard directory >= 0 else { throw HandoffFailure.unavailable }
    defer { close(directory) }
    guard fsync(directory) == 0 else { throw HandoffFailure.unavailable }
  }
  func append(_ records: [HandoffRecord], consent: Bool) throws {
    guard consent else { throw HandoffFailure.approvalRequired }
    guard !records.isEmpty else { throw HandoffFailure.invalidInput }
    for record in records { try record.validate() }
    try locked {
      var all = records
      for file in try files() { all += try read(file).records } // Damaged storage blocks new staging.
      guard all.count <= Self.maxCount, all.reduce(0, { $0 + $1.bytes.count }) <= Self.maxBytes,
        Set(all.map { $0.id }).count == all.count else { throw HandoffFailure.full }
      try atomicWrite(HandoffBatch(version: 1, records: records), to: root.appendingPathComponent(UUID().uuidString.lowercased() + ".json"))
    }
  }
  func entries() throws -> [HandoffEntry] {
    try locked {
      var result: [HandoffEntry] = []
      for file in try files() {
        do { result += try read(file).records.map { HandoffEntry(id: $0.id, record: $0, error: nil) } }
        catch { result.append(HandoffEntry(id: "batch:" + file.deletingPathExtension().lastPathComponent, record: nil,
          error: "Unreadable handoff batch. No source was imported. Discard removes this damaged batch; reshare the originals.")) }
      }
      return result
    }
  }
  func remove(_ id: String) throws {
    try locked {
      if id.hasPrefix("batch:") {
        let batchID = String(id.dropFirst(6)); guard Self.uuid(batchID) else { throw HandoffFailure.invalidInput }
        let file = root.appendingPathComponent(batchID + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        // A damaged-batch delete must never silently become a valid batch delete.
        if (try? read(file)) != nil { throw HandoffFailure.invalidInput }
        try FileManager.default.removeItem(at: file); return
      }
      guard Self.uuid(id) else { throw HandoffFailure.invalidInput }
      for file in try files() {
        guard let batch = try? read(file), batch.records.contains(where: { $0.id == id }) else { continue }
        let kept = batch.records.filter { $0.id != id }
        if kept.isEmpty { try FileManager.default.removeItem(at: file) }
        else { try atomicWrite(HandoffBatch(version: 1, records: kept), to: file) }
        return
      }
      // Lost response after successful deletion: safe idempotent replay.
    }
  }
}
