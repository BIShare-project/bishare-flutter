import Flutter
import UIKit
import UserNotifications

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
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
