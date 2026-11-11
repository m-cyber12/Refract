import Foundation
import UniformTypeIdentifiers

/// Provider decoding only; no storage, parser or networking. Caller obtains consent.
enum HandoffProvider {
  private static func format(_ name: String) throws -> String {
    switch URL(fileURLWithPath: name).pathExtension.lowercased() {
    case "pdf": return "pdf"
    case "md", "markdown": return "markdown"
    case "html", "htm": return "html"
    case "txt", "csv", "tsv", "json", "xml": return "text"
    default: throw HandoffFailure.invalidInput
    }
  }
  private static func read(_ url: URL, format: String) throws -> Data {
    guard url.isFileURL else { throw HandoffFailure.invalidInput }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    let temporaryRoot = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().standardizedFileURL.path
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
    // Do not let a provider turn a forged file URL into a read of our private
    // App Group/container files. Outside vended temporary files, require scope.
    guard access || resolved.hasPrefix(temporaryRoot + "/") else { throw HandoffFailure.invalidInput }
    guard let stream = InputStream(url: url) else { throw HandoffFailure.invalidInput }
    stream.open(); defer { stream.close() }
    let cap = (format == "pdf" ? 10 : 2) * 1024 * 1024
    var data = Data(); var buffer = [UInt8](repeating: 0, count: 16384)
    while true {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count >= 0 else { throw HandoffFailure.invalidInput }; if count == 0 { break }
      guard data.count + count <= cap else { throw HandoffFailure.full }
      data.append(contentsOf: buffer.prefix(count))
    }
    return data
  }
  static func load(_ provider: NSItemProvider, consentTS: Int64) async throws -> HandoffRecord {
    let suggestedName = provider.suggestedName
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      return try await withCheckedThrowingContinuation { continuation in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          do {
            // NSItemProvider can vend a file URL as a URL object or UTF-8 URL data.
            let url: URL?
            if let value = item as? URL { url = value }
            else if let data = item as? Data, let value = String(data: data, encoding: .utf8) { url = URL(string: value) }
            else { url = nil }
            guard let url, url.isFileURL else { throw HandoffFailure.invalidInput }
            let kind = try (try? format(url.lastPathComponent)) ?? format(suggestedName ?? "")
            continuation.resume(returning: try HandoffRecord(name: url.lastPathComponent, format: kind, bytes: read(url, format: kind), consentTS: consentTS))
          } catch { continuation.resume(throwing: error) }
        }
      }
    }
    let types: [(String, String)] = [(UTType.pdf.identifier, "pdf"), ("net.daringfireball.markdown", "markdown"), (UTType.html.identifier, "html"), ("public.comma-separated-values-text", "text"), ("public.tab-separated-values-text", "text"), (UTType.json.identifier, "text"), (UTType.xml.identifier, "text")]
    for (type, kind) in types where provider.hasItemConformingToTypeIdentifier(type) {
      return try await withCheckedThrowingContinuation { continuation in
        // Read inside the callback: temporary provider URLs expire on return.
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
          do {
            guard let url else { throw HandoffFailure.invalidInput }
            continuation.resume(returning: try HandoffRecord(name: suggestedName ?? "Shared \(kind)", format: kind, bytes: read(url, format: kind), consentTS: consentTS))
          } catch { continuation.resume(throwing: error) }
        }
      }
    }
    let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
    guard provider.hasItemConformingToTypeIdentifier(type) else { throw HandoffFailure.invalidInput }
    if type == UTType.plainText.identifier {
      let fileRecord: HandoffRecord? = try await withCheckedThrowingContinuation { continuation in
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
          guard let url else { continuation.resume(returning: nil); return }
          do {
            let kind = (try? format(url.lastPathComponent)) ?? (try? format(suggestedName ?? "")) ?? "text"
            continuation.resume(returning: try HandoffRecord(name: suggestedName ?? url.lastPathComponent,
              format: kind, bytes: read(url, format: kind), consentTS: consentTS))
          } catch { continuation.resume(throwing: error) }
        }
      }
      if let fileRecord { return fileRecord } // Preserve a text file's BOM/raw bytes.
    }
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
        do {
          let bytes: Data
          if let url = item as? URL {
            if url.isFileURL {
              guard type == UTType.plainText.identifier else { throw HandoffFailure.invalidInput }
              let kind = (try? format(url.lastPathComponent)) ?? (try? format(suggestedName ?? "")) ?? "text"
              continuation.resume(returning: try HandoffRecord(name: suggestedName ?? url.lastPathComponent,
                format: kind, bytes: read(url, format: kind), consentTS: consentTS)); return
            }
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw HandoffFailure.invalidInput }
            bytes = Data(url.absoluteString.utf8) // Address only. Never fetched.
          } else if let text = item as? String { bytes = Data(text.utf8) }
          else if let data = item as? Data { bytes = data }
          else { throw HandoffFailure.invalidInput }
          continuation.resume(returning: try HandoffRecord(name: suggestedName ?? "Shared text or address", format: "text", bytes: bytes, consentTS: consentTS))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
