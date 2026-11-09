import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let handoffQueue = DispatchQueue(label: "dev.refract.ios-handoff")
  private var delivered = Set<String>() // Session acknowledgement, NEVER disk deletion.
  private var shareChannel: FlutterMethodChannel?

  override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RefractHandoff") else { return }
    let channel = FlutterMethodChannel(name: "dev.refract/shared", binaryMessenger: registrar.messenger())
    shareChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "handoff_unavailable", message: "Handoff engine unavailable.", details: nil)); return }
      self.handoffQueue.async {
        do {
          let response: Any?
          switch call.method {
          case "beginShareSession": self.delivered.removeAll(); response = nil
          case "peekShare":
            let legacy = UserDefaults(suiteName: HandoffStore.group)?.string(forKey: "pendingShare")
            let notice = legacy == nil ? nil : "Legacy handoff found: prior consent was not recorded. Review or discard it. No new legacy copy was created."
            if let legacy, !self.delivered.contains("legacy-pending-share") {
              var entry: [String: Any] = ["id": "legacy-pending-share", "staged": true, "name": "Legacy handoff (consent not recorded)"]
              let bytes = Data(legacy.utf8)
              if bytes.isEmpty || bytes.count > 2 * 1024 * 1024 { entry["error"] = "Legacy input is empty or oversized. Discard it and share again with explicit consent." }
              else { entry["format"] = "text"; entry["bytes"] = FlutterStandardTypedData(bytes: bytes) }
              response = ["draft": entry, "notice": notice as Any? ?? NSNull()]
            } else {
              let next = try HandoffStore.appGroup().entries().first { !self.delivered.contains($0.id) }
              var packet: [String: Any] = ["notice": notice as Any? ?? NSNull()]
              if let next {
                var entry: [String: Any] = ["id": next.id, "staged": true]
                if let record = next.record {
                  entry["name"] = record.name; entry["format"] = record.format
                  entry["bytes"] = FlutterStandardTypedData(bytes: record.bytes); entry["consent_ts"] = record.consentTS
                } else { entry["error"] = next.error ?? "Unreadable staged handoff." }
                packet["draft"] = entry
              }
              response = packet
            }
          case "ackShare":
            guard let id = call.arguments as? String, id.count <= 128 else { throw HandoffFailure.invalidInput }
            self.delivered.insert(id); response = nil
          case "deleteShare":
            guard let id = call.arguments as? String else { throw HandoffFailure.invalidInput }
            if id == "legacy-pending-share" { UserDefaults(suiteName: HandoffStore.group)?.removeObject(forKey: "pendingShare") }
            else { try HandoffStore.appGroup().remove(id) }
            self.delivered.remove(id); response = nil
          case "clearShareNotice": response = nil
          default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
          }
          DispatchQueue.main.async { result(response) }
        } catch {
          // No provider path, filename, source snippet or parser diagnostic in errors.
          DispatchQueue.main.async { result(FlutterError(code: "handoff_storage", message: "iOS handoff storage unavailable. Unlock the device and verify App Group provisioning. Existing copies were not intentionally discarded; retry or use Import.", details: nil)) }
        }
      }
    }
  }
}
