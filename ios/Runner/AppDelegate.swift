import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications: without the delegate, the plugin's
    // willPresent handler never runs, so notifications don't show in the
    // foreground (the common case — a file arrives while the app is open).
    // FlutterAppDelegate conforms to UNUserNotificationCenterDelegate and forwards
    // to the plugin.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    // Drive photo backup while the app is closed (VaultBackground in Dart).
    // The task handler must be registered before launch finishes, and the
    // background engine needs the plugins the run uses.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "app.bishare.vault.backup")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// The time iOS gives an app that leaves the screen while a Drive file is
  /// going up (VaultBackground.extraTime in Dart).
  private var uploadTime: UIBackgroundTaskIdentifier = .invalid

  private func beginUploadTime() {
    guard uploadTime == .invalid else { return }
    uploadTime = UIApplication.shared.beginBackgroundTask(withName: "Drive uploads") { [weak self] in
      self?.endUploadTime()
    }
  }

  private func endUploadTime() {
    guard uploadTime != .invalid else { return }
    UIApplication.shared.endBackgroundTask(uploadTime)
    uploadTime = .invalid
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Drive uploads: the file in flight finishes after the app leaves the
    // screen, within the time iOS gives (about 30 seconds).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BIShareBackgroundTime") {
      let channel = FlutterMethodChannel(
        name: "app.bishare/background", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "begin":
          self?.beginUploadTime()
          result(nil)
        case "end":
          self?.endUploadTime()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    // Offline "Nearby" over MultipeerConnectivity. Add BIShareNearbyPlugin.swift
    // to the iOS Runner target in Xcode for this to compile.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BIShareNearbyPlugin") {
      BIShareNearbyPlugin.register(with: registrar)
    }
    // Image clipboard for Universal Clipboard sync (Flutter's Clipboard API is
    // text-only). See ClipboardImageChannel on the Dart side. Registered here —
    // where the app's channels are wired — like the nearby plugin above.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BIShareClipboard") {
      let channel = FlutterMethodChannel(
        name: "app.bishare/clipboard", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "getImage":
          // pngData() re-encodes whatever UIPasteboard decoded → portable bytes.
          if let image = UIPasteboard.general.image, let png = image.pngData(), !png.isEmpty {
            result(["bytes": FlutterStandardTypedData(bytes: png), "mime": "image/png"])
          } else {
            result(nil)
          }
        case "setImage":
          let args = call.arguments as? [String: Any]
          if let data = (args?["bytes"] as? FlutterStandardTypedData)?.data,
             let image = UIImage(data: data) {
            UIPasteboard.general.image = image
            result(true)
          } else {
            result(false)
          }
        case "changeCount":
          result(UIPasteboard.general.changeCount)
        case "setSecretText":
          // Local only (never to the other Apple devices) and gone by itself.
          let args = call.arguments as? [String: Any]
          guard let text = args?["text"] as? String else { result(false); return }
          let seconds = (args?["seconds"] as? Int) ?? 60
          UIPasteboard.general.setItems(
            [["public.utf8-plain-text": text]],
            options: [
              .localOnly: true,
              .expirationDate: Date().addingTimeInterval(TimeInterval(seconds)),
            ])
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
