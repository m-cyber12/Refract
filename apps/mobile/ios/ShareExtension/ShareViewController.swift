import UIKit

/// REFRACT Share Extension (iOS). Accepts shared text/URLs, stores them in the
/// shared App Group container and opens the main app, which picks the content
/// up. The extension never uploads anything (spec §12, C5).
class ShareViewController: UIViewController {

  override func viewDidLoad() {
    super.viewDidLoad()
    Task { await forward() }
  }

  private func forward() async {
    guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
          let provider = item.attachments?.first else { complete(); return }

    var text: String?
    if provider.hasItemConformingToTypeIdentifier("public.url") {
      if let url = await loadItem(provider, "public.url") as? URL {
        text = url.absoluteString
      }
    }
    if text == nil, provider.hasItemConformingToTypeIdentifier("public.plain-text") {
      text = await loadItem(provider, "public.plain-text") as? String
    }
    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      UserDefaults(suiteName: "group.dev.refract")?.set(text, forKey: "pendingShare")
      var url = URLComponents(string: "refract://share")
      if let u = url?.url { UIApplication.shared.open(u) }
    }
    complete()
  }

  private func loadItem(_ provider: NSItemProvider, _ type: String) async -> Any? {
    await withCheckedContinuation { cont in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in cont.resume(returning: item) }
    }
  }

  private func complete() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
