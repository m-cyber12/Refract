import Foundation
import Darwin

func record(_ text: String = "Synthetic café 東京") throws -> HandoffRecord {
  try HandoffRecord(name: "source.txt", format: "text", bytes: Data(text.utf8))
}
func check(_ value: @autoclosure () throws -> Bool) rethrows { let result = try value(); precondition(result) }
func mustFail(_ work: () throws -> Void) { do { try work(); fatalError("Expected failure") } catch {} }
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--writer" {
  do { try HandoffStore(root: URL(fileURLWithPath: CommandLine.arguments[2])).append([record()], consent: true); exit(0) }
  catch { exit(1) }
}
let root = FileManager.default.temporaryDirectory.appendingPathComponent("refract-handoff-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let store = HandoffStore(root: root)
let first = try record("\u{FEFF}# Exact BOM 東京")
mustFail { try store.append([first], consent: false) }
try check((try store.entries()).isEmpty)
try store.append([first], consent: true)
let reopened = HandoffStore(root: root)
try check(try reopened.entries().first!.record!.bytes == first.bytes)
// Reading/delivering cannot delete; a separate explicit decision is required.
try check(try reopened.entries().count == 1)
let pdf = try HandoffRecord(name: "binary.pdf", format: "pdf", bytes: Data([37,80,68,70,255,0,128]))
try reopened.append([pdf], consent: true)
try check(try reopened.entries().contains { $0.record?.bytes == pdf.bytes })
try reopened.remove(first.id); try reopened.remove(first.id)
try check(try reopened.entries().count == 1)
mustFail { try reopened.remove("../../outside") }
mustFail { _ = try HandoffRecord(name: "bad.txt", format: "text", bytes: Data([255])) }
mustFail { _ = try HandoffRecord(name: "huge.pdf", format: "pdf", bytes: Data(repeating: 0, count: 10*1024*1024+1)) }
mustFail { _ = try HandoffRecord(name: "a.docx", format: "docx", bytes: Data([1])) }
// A killed writer's private temporary file is reconciled, never a published batch.
let pending = root.appendingPathComponent(".pending-" + UUID().uuidString.lowercased())
try Data([1,2,3]).write(to: pending)
try check(try reopened.entries().count == 1); precondition(!FileManager.default.fileExists(atPath: pending.path))
try reopened.remove(pdf.id)
// Separate processes race real append operations under flock, not in-memory locks.
var children: [Process] = []
for _ in 0..<16 {
  let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["--writer", root.path]
  try child.run(); children.append(child)
}
for child in children { child.waitUntilExit(); precondition(child.terminationStatus == 0) }
try check(try reopened.entries().count == 16)
mustFail { try reopened.append([record()], consent: true) }
for entry in try reopened.entries() { try reopened.remove(entry.id) }
// Byte cap is independent of the item cap, and rejected batches publish nothing.
let big = try HandoffRecord(name: "ten.pdf", format: "pdf", bytes: Data(repeating: 42, count: 10*1024*1024))
try reopened.append([big], consent: true)
let big2 = try HandoffRecord(name: "ten2.pdf", format: "pdf", bytes: big.bytes)
try reopened.append([big2], consent: true)
let big3 = try HandoffRecord(name: "ten3.pdf", format: "pdf", bytes: big.bytes)
mustFail { try reopened.append([big3], consent: true) }
try check(try reopened.entries().count == 2)
for entry in try reopened.entries() { try reopened.remove(entry.id) }
let corrupt = root.appendingPathComponent(UUID().uuidString.lowercased() + ".json")
try Data("damaged".utf8).write(to: corrupt)
let damaged = try reopened.entries().first!
precondition(damaged.error != nil && damaged.record == nil)
mustFail { try reopened.append([record()], consent: true) }
try reopened.remove(damaged.id)
try check(try reopened.entries().isEmpty)
// Damaged entries must never follow a symlink to a valid staged batch or block
// waiting for a FIFO writer. Explicit discard is scoped to the damaged name.
let retained = try record("Retained source")
try reopened.append([retained], consent: true)
let valid = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.pathExtension == "json" }!
let linkID = UUID().uuidString.lowercased(); let link = root.appendingPathComponent(linkID + ".json")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
let linkEntry = try reopened.entries().first { $0.id == "batch:" + linkID }!
precondition(linkEntry.record == nil && linkEntry.error != nil)
mustFail { try reopened.append([record()], consent: true) }
try reopened.remove(linkEntry.id)
try check(try reopened.entries().contains { $0.record?.id == retained.id })
let danglingID = UUID().uuidString.lowercased(); let dangling = root.appendingPathComponent(danglingID + ".json")
try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("missing"))
try check(try reopened.entries().contains { $0.id == "batch:" + danglingID && $0.error != nil })
try reopened.remove("batch:" + danglingID)
var danglingInfo = stat(); precondition(lstat(dangling.path, &danglingInfo) != 0 && errno == ENOENT)
let fifoID = UUID().uuidString.lowercased(); let fifo = root.appendingPathComponent(fifoID + ".json")
precondition(mkfifo(fifo.path, 0o600) == 0)
try check(try reopened.entries().contains { $0.id == "batch:" + fifoID && $0.error != nil })
try reopened.remove("batch:" + fifoID)
let largeID = UUID().uuidString.lowercased(); let oversized = root.appendingPathComponent(largeID + ".json")
let largeFD = open(oversized.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
precondition(largeFD >= 0 && ftruncate(largeFD, 40 * 1024 * 1024 + 1) == 0); close(largeFD)
try check(try reopened.entries().contains { $0.id == "batch:" + largeID && $0.error != nil })
try reopened.remove("batch:" + largeID)
try check(try reopened.entries().count == 1)
try reopened.remove(retained.id); try check(try reopened.entries().isEmpty)
print("PASS: explicit consent, process restart/read retention, binary/BOM identity, explicit idempotent deletion, format/size limits, interrupted temporary cleanup, 16-process atomic publication/capacity, and damaged-batch recovery")
