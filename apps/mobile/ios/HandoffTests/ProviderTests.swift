import Foundation
import UniformTypeIdentifiers

@main struct ProviderTests {
  static func load(_ provider: NSItemProvider, _ name: String, _ consentTS: Int64) async -> HandoffRecord {
    FileHandle.standardOutput.write(Data("Testing provider: \(name)\n".utf8))
    do { return try await HandoffProvider.load(provider, consentTS: consentTS) }
    catch { print("::error title=provider-case::\(name): \(error)"); exit(1) }
  }
  static func ensure(_ value: Bool, _ name: String) {
    if !value { print("::error title=provider-identity::\(name): unexpected bytes, format or consent time"); exit(1) }
  }
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("refract-provider-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cases: [(String, String, String, Data)] = [
      ("source.pdf", UTType.pdf.identifier, "pdf", Data([37,80,68,70,255,0,128])),
      ("source.md", "net.daringfireball.markdown", "markdown", Data("\u{FEFF}# Source 東京".utf8)),
      ("source.html", UTType.html.identifier, "html", Data("<p>1 &lt; 2</p>".utf8)),
      ("source.txt", UTType.plainText.identifier, "text", Data("\u{FEFF}Exact text café".utf8)),
      ("table.csv", "public.comma-separated-values-text", "text", Data("\u{FEFF}name,value\r\nAlice,1\r\n".utf8)),
      ("table.tsv", "public.tab-separated-values-text", "text", Data("name\tvalue\r\nAlice\t1\r\n".utf8)),
      ("source.json", UTType.json.identifier, "text", Data("\u{FEFF}{\"name\":\"東京\"}\r\n".utf8)),
      ("source.xml", UTType.xml.identifier, "text", Data("<root>source</root>\r\n".utf8)),
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
      let record = await load(provider, name, 42)
      ensure(record.format == kind && record.bytes == bytes && record.consentTS == 42, name)
    }
    let address = NSItemProvider()
    address.registerItem(forTypeIdentifier: UTType.url.identifier, loadHandler: { callback, _, _ in
      callback?(URL(string: "https://example.invalid/unfetched?source=fixture")! as NSURL, nil)
    })
    let url = await load(address, "unfetched-url", 43)
    ensure(String(data: url.bytes, encoding: .utf8) == "https://example.invalid/unfetched?source=fixture" && url.format == "text", "unfetched-url")
    // Original file URL path, not just advertised PDF/text representations.
    let original = root.appendingPathComponent("original.csv"); let originalBytes = Data("\u{FEFF}name,value\r\nAlice,1\r\n".utf8); try originalBytes.write(to: original)
    let fileURL = NSItemProvider()
    fileURL.registerItem(forTypeIdentifier: UTType.fileURL.identifier, loadHandler: { callback, _, _ in callback?(original as NSURL, nil) })
    let raw = await load(fileURL, "file-url", 44)
    ensure(raw.bytes == originalBytes && raw.format == "text", "file-url")
    print("PASS: real NSItemProvider PDF/Markdown/HTML/TXT/CSV/TSV/JSON/XML/file-URL callbacks, exact binary/BOM bytes, unfetched address, and explicit consent timestamp")
  }
}
