import UIKit
import UniformTypeIdentifiers

/// Consent precedes provider loading and every app-owned content write.
/// No UIApplication.shared, custom-scheme launch, parser, network or library DB.
final class ShareViewController: UIViewController {
  private let status = UILabel()
  private let approve = UIButton(type: .system)
  private let cancel = UIButton(type: .system)
  private var providers: [NSItemProvider] = []
  private var busy = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    status.numberOfLines = 0
    status.text = "Copy \(providers.count) shared item(s) for later review?\n\nSupported: text, unfetched HTTP(S) addresses, UTF-8 TXT/Markdown/HTML and PDF. Up to 16 items / 24 MiB total; text 2 MiB, PDF 10 MiB.\n\nOnly if you approve: complete input copies will be stored in REFRACT's shared app container without app-level encryption until saved or explicitly discarded. iOS device protection is a separate layer. Providers may download/cache files. No automatic expiry or secure-erasure promise.\n\nThis approves a handoff copy, NOT a library save. Open REFRACT manually afterwards to preview and approve each library save."
    approve.setTitle("Approve handoff copy", for: .normal)
    approve.addTarget(self, action: #selector(stage), for: .touchUpInside)
    cancel.setTitle("Not now", for: .normal)
    cancel.addTarget(self, action: #selector(finish), for: .touchUpInside)
    let stack = UIStackView(arrangedSubviews: [status, approve, cancel]); stack.axis = .vertical; stack.spacing = 16
    let scroll = UIScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll); scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
    ])
    approve.isEnabled = !providers.isEmpty && providers.count <= HandoffStore.maxCount
  }
  @objc private func finish() { if !busy { extensionContext?.completeRequest(returningItems: [], completionHandler: nil) } }
  @objc private func stage() {
    guard !busy else { return }; busy = true; approve.isEnabled = false; cancel.isEnabled = false
    let consentTS = Int64(Date().timeIntervalSince1970)
    Task {
      do {
        var records: [HandoffRecord] = []
        for provider in providers {
          let record = try await Self.load(provider, consentTS: consentTS)
          guard records.reduce(0, { $0 + $1.bytes.count }) + record.bytes.count <= HandoffStore.maxBytes else { throw HandoffFailure.full }
          records.append(record)
        }
        // A bounded batch publishes atomically, never a silently partial selection.
        let ready = records
        try await Task.detached { try HandoffStore.appGroup().append(ready, consent: true) }.value
        status.text = "Handoff copies are ready. Open REFRACT manually and choose Review shares. Nothing has been added to the library. Copies remain until saved or explicitly discarded."
        approve.isHidden = true; cancel.setTitle("Done", for: .normal)
      } catch {
        status.text = "Handoff could not be confirmed. Check REFRACT's Shared drafts before retrying: a process/storage interruption can leave an approved copy. Unsupported, unreadable, invalid UTF-8, oversized items or full/unavailable shared storage require a smaller supported re-share. No library original was saved."
        approve.isEnabled = true
      }
      busy = false; cancel.isEnabled = true
    }
  }
  nonisolated private static func format(_ name: String) throws -> String {
    switch URL(fileURLWithPath: name).pathExtension.lowercased() {
    case "pdf": return "pdf"
    case "md", "markdown": return "markdown"
    case "html", "htm": return "html"
    case "txt": return "text"
    default: throw HandoffFailure.invalidInput
    }
  }
  nonisolated private static func read(_ url: URL, format: String) throws -> Data {
    guard url.isFileURL else { throw HandoffFailure.invalidInput }
    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
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
  nonisolated private static func load(_ provider: NSItemProvider, consentTS: Int64) async throws -> HandoffRecord {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      return try await withCheckedThrowingContinuation { continuation in
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
          do {
            guard let url = item as? URL, url.isFileURL else { throw HandoffFailure.invalidInput }
            let kind = try format(url.lastPathComponent)
            continuation.resume(returning: try HandoffRecord(name: url.lastPathComponent, format: kind, bytes: read(url, format: kind), consentTS: consentTS))
          } catch { continuation.resume(throwing: error) }
        }
      }
    }
    let types: [(String, String)] = [(UTType.pdf.identifier, "pdf"), ("net.daringfireball.markdown", "markdown"), (UTType.html.identifier, "html")]
    for (type, kind) in types where provider.hasItemConformingToTypeIdentifier(type) {
      return try await withCheckedThrowingContinuation { continuation in
        // Read inside the callback: temporary provider URLs expire on return.
        provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
          do {
            guard let url else { throw HandoffFailure.invalidInput }
            continuation.resume(returning: try HandoffRecord(name: provider.suggestedName ?? "Shared \(kind)", format: kind, bytes: read(url, format: kind), consentTS: consentTS))
          } catch { continuation.resume(throwing: error) }
        }
      }
    }
    let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
    guard provider.hasItemConformingToTypeIdentifier(type) else { throw HandoffFailure.invalidInput }
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
        do {
          let bytes: Data
          if let url = item as? URL {
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw HandoffFailure.invalidInput }
            bytes = Data(url.absoluteString.utf8) // Address only. Never fetched.
          } else if let text = item as? String { bytes = Data(text.utf8) }
          else if let data = item as? Data { bytes = data }
          else { throw HandoffFailure.invalidInput }
          continuation.resume(returning: try HandoffRecord(name: provider.suggestedName ?? "Shared text or address", format: "text", bytes: bytes, consentTS: consentTS))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}
