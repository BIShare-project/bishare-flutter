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

  /// The same for a LAN send or receive (TransferKeepAlive in Dart): it
  /// keeps going for the time iOS gives after the screen locks, then pauses
  /// and continues from where it stopped when BIShare is opened again.
  private var transferTime: UIBackgroundTaskIdentifier = .invalid

  /// Localized "Transfer paused" / "Open BIShare to continue", from Dart.
  private var pausedNotice: (title: String, body: String)?

  /// A transfer is running (between transferStart and transferEnd).
  private var transferActive = false
  private var foregroundObserver: NSObjectProtocol?

  /// Back on screen mid-transfer: a fresh grant of background time for the
  /// next lock, and the "paused" notice is no longer true.
  private func watchForeground() {
    guard foregroundObserver == nil else { return }
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self, self.transferActive else { return }
      UNUserNotificationCenter.current().removeDeliveredNotifications(
        withIdentifiers: ["bishare.transfer.paused"])
      self.beginTransferTime()
    }
  }

  private func beginTransferTime() {
    guard transferTime == .invalid else { return }
    transferTime = UIApplication.shared.beginBackgroundTask(withName: "LAN transfer") { [weak self] in
      // iOS's time is up with the transfer still running: say it paused,
      // so the user knows to open BIShare (it continues from where it was).
      self?.postPausedNotice()
      self?.endTransferTime()
    }
  }

  private func postPausedNotice() {
    guard let notice = pausedNotice else { return }
    let content = UNMutableNotificationContent()
    content.title = notice.title
    content.body = notice.body
    let request = UNNotificationRequest(
      identifier: "bishare.transfer.paused", content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  private func endTransferTime() {
    guard transferTime != .invalid else { return }
    UIApplication.shared.endBackgroundTask(transferTime)
    transferTime = .invalid
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
        case "transferStart":
          // A transfer is running: the screen does not dim and lock by
          // itself, and a manual lock still gets iOS's extra time.
          UIApplication.shared.isIdleTimerDisabled = true
          if let args = call.arguments as? [String: Any],
            let title = args["pausedTitle"] as? String,
            let body = args["pausedBody"] as? String
          {
            self?.pausedNotice = (title, body)
          }
          self?.transferActive = true
          self?.watchForeground()
          self?.beginTransferTime()
          result(nil)
        case "transferEnd":
          UIApplication.shared.isIdleTimerDisabled = false
          self?.transferActive = false
          self?.endTransferTime()
          // Done (or back on screen): the "paused" notice is no longer true.
          UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["bishare.transfer.paused"])
          result(nil)
        case "excludeFromBackup":
          // Drive's work folder: plain copies of files being uploaded.
          guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
            result(false)
            return
          }
          var url = URL(fileURLWithPath: path, isDirectory: true)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          do {
            try url.setResourceValues(values)
            result(true)
          } catch {
            result(false)
          }
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
    // iPhone Duo hinge and fold (DevicePosturePlugin below; device_posture.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DevicePosturePlugin") {
      DevicePosturePlugin.register(with: registrar)
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

// MARK: - iPhone Duo hinge and fold

/// The iPhone Duo's hinge and fold, for Dart (lib/core/ui/device_posture.dart).
///
/// `app.bishare/posture/events` streams the state whenever the hinge moves;
/// `app.bishare/posture` answers `state` on demand (Dart asks again when the
/// window changes size, since the fold's rect turns with the screen).
///
/// The state is `{status, angle, folds}`: status `closed`, `partial`, `full`
/// or `unknown`; folds are the active division regions (the crease while the
/// device is half open, empty when it lies flat) as `[x, y, w, h]` in points,
/// which are Flutter's logical pixels. The hinge API is iOS 27.1 and builds
/// only with the iOS 27 SDK (Swift 6.4); older Xcodes compile a plugin that
/// reports `unknown` with no folds, so every other device keeps its layout.
final class DevicePosturePlugin: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var interaction: UIInteraction?
  private var status = "unknown"
  private var angle: Double = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = DevicePosturePlugin()
    FlutterEventChannel(
      name: "app.bishare/posture/events", binaryMessenger: registrar.messenger()
    ).setStreamHandler(instance)
    FlutterMethodChannel(
      name: "app.bishare/posture", binaryMessenger: registrar.messenger()
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "state":
        instance.attach()
        result(instance.state())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    attach()
    events(state())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    if let i = interaction, let view = i.view { view.removeInteraction(i) }
    interaction = nil
    return nil
  }

  /// The Flutter view: the root view of the app's key window.
  private func hostView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
        return window.rootViewController?.view
      }
    }
    return nil
  }

  /// Start hinge updates (once the Flutter view exists).
  private func attach() {
    guard interaction == nil else { return }
    #if compiler(>=6.4)
      if #available(iOS 27.1, *), let view = hostView() {
        let hinge = UIHingeInteraction { [weak self] _, update in
          guard let self else { return }
          if let h = update.hinge {
            switch h.status {
            case .closed: self.status = "closed"
            case .partiallyOpen: self.status = "partial"
            case .fullyOpen: self.status = "full"
            default: self.status = "unknown"
            }
            self.angle = Double(h.angle)
          } else {
            self.status = "unknown"
          }
          self.sink?(self.state())
        }
        view.addInteraction(hinge)
        interaction = hinge
      }
    #endif
  }

  private func state() -> [String: Any] {
    var folds: [[Double]] = []
    #if compiler(>=6.4)
      if #available(iOS 27.1, *), let view = hostView() {
        folds = view.reservedRegions(kind: .division)
          .filter { $0.isActive }
          .map { r in
            [Double(r.frame.minX), Double(r.frame.minY), Double(r.frame.width), Double(r.frame.height)]
          }
      }
    #endif
    return ["status": status, "angle": angle, "folds": folds]
  }
}
