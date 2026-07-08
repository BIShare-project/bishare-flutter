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
  }
}
