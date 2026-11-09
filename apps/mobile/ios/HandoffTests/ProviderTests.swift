import Foundation
import UniformTypeIdentifiers

@main struct ProviderTests {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("refract-provider-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cases: [(String, String, String, Data)] = [
      ("source.pdf", UTType.pdf.identifier, "pdf", Data([37,80,68,70,255,0,128])),
      ("source.md", "net.daringfireball.markdown", "markdown", Data("\u{FEFF}# Source 東京".utf8)),
      ("source.html", UTType.html.identifier, "html", Data("<p>1 &lt; 2</p>".utf8)),
      ("source.txt", UTType.plainText.identifier, "text", Data("\u{FEFF}Exact text café".utf8)),
    ]
    for (name, type, kind, bytes) in cases {
      let file = root.appendingPathComponent(name); try bytes.write(to: file)
      // Real NSItemProvider file representation callbacks. Copy bytes while the
      // provider's callback authorizes the temporary URL; never reopen it later.
      let provider = NSItemProvider()
      provider.suggestedName = name
      provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { callback in
        callback(file, false, nil); return nil
      }
      let record = try await HandoffProvider.load(provider, consentTS: 42)
      precondition(record.format == kind && record.bytes == bytes && record.consentTS == 42)
    }
    let address = NSItemProvider()
    address.registerItem(forTypeIdentifier: UTType.url.identifier, loadHandler: { callback, _, _ in
      callback(URL(string: "https://example.invalid/unfetched?source=fixture")! as NSURL, nil)
    })
    let url = try await HandoffProvider.load(address, consentTS: 43)
    precondition(String(data: url.bytes, encoding: .utf8) == "https://example.invalid/unfetched?source=fixture" && url.format == "text")
    // Original file URL path, not just advertised PDF/text representations.
    let original = root.appendingPathComponent("original.md"); let originalBytes = Data("\u{FEFF}# Original".utf8); try originalBytes.write(to: original)
    let fileURL = NSItemProvider()
    fileURL.registerItem(forTypeIdentifier: UTType.fileURL.identifier, loadHandler: { callback, _, _ in callback(original as NSURL, nil) })
    let raw = try await HandoffProvider.load(fileURL, consentTS: 44)
    precondition(raw.bytes == originalBytes && raw.format == "markdown")
    print("PASS: real NSItemProvider PDF/Markdown/HTML/TXT/file-URL callbacks, exact binary/BOM bytes, unfetched address, and explicit consent timestamp")
  }
}
