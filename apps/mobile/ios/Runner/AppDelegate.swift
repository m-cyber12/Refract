import Flutter
import UIKit

/// Forwards content delivered by the REFRACT Share Extension (via App Group
/// + custom URL scheme) to the Flutter layer. Platform-honest: the share
/// extension is the only supported iOS intake surface (spec §12).
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "dev.refract/shared",
      binaryMessenger: controller!.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "sharedText", let text = call.arguments as? String {
        // Handled by Dart; nothing to do natively here.
      }
      result(nil)
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "refract", url.host == "share" {
      if let text = UserDefaults(suiteName: "group.dev.refract")?.string(forKey: "pendingShare") {
        let controller = window?.rootViewController as? FlutterViewController
        FlutterMethodChannel(name: "dev.refract/shared", binaryMessenger: controller!.binaryMessenger)
          .invokeMethod("sharedText", arguments: text)
        UserDefaults(suiteName: "group.dev.refract")?.removeObject(forKey: "pendingShare")
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
