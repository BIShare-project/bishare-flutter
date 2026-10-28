import Flutter
import UIKit
import UniformTypeIdentifiers
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

  private let docFolder = DocFolder()

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
    // The Send tab's Documents folder (DocFolder below).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BIShareDocFolder") {
      let channel = FlutterMethodChannel(
        name: "app.bishare/folder", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        self?.docFolder.handle(call, result: result)
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

/// The folder the Send tab's Documents list reads (redesign-plan.md 3.6b).
///
/// The person picks one folder in Files (UIDocumentPickerViewController in
/// folder mode); a security-scoped bookmark keeps the grant across launches,
/// as the macOS save folder does. Listing and copying open the scope only
/// for as long as they run. A file is copied to tmp only when it is chosen,
/// because the sender needs a real path.
///
/// Methods on `app.bishare/folder`: docsRestore, docsPick, docsList, docsCopy,
/// docsClear (the same names as Android's DocFolder.kt).
final class DocFolder: NSObject, UIDocumentPickerDelegate {
  private let bookmarkKey = "bishare.docFolderBookmark"
  private let maxDepth = 4
  private let maxFiles = 3000
  private var pendingPick: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "docsRestore":
      result(resolve().map(describe))
    case "docsPick":
      pick(result)
    case "docsList":
      background(result) { self.list() }
    case "docsCopy":
      guard let id = (call.arguments as? [String: Any])?["id"] as? String else {
        result(nil)
        return
      }
      background(result) { self.copy(path: id) }
    case "docsClear":
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func pick(_ result: @escaping FlutterResult) {
    pendingPick?(nil)
    pendingPick = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    guard let top = Self.topController() else {
      pendingPick = nil
      result(nil)
      return
    }
    top.present(picker, animated: true)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first, url.startAccessingSecurityScopedResource() else {
      result(nil)
      return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    guard let data = try? url.bookmarkData() else {
      result(nil)
      return
    }
    UserDefaults.standard.set(data, forKey: bookmarkKey)
    result(describe(url))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingPick?(nil)
    pendingPick = nil
  }

  /// The granted folder, refreshing a stale bookmark; nil when none or gone.
  private func resolve() -> URL? {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      return nil
    }
    if stale, url.startAccessingSecurityScopedResource() {
      if let fresh = try? url.bookmarkData() {
        UserDefaults.standard.set(fresh, forKey: bookmarkKey)
      }
      url.stopAccessingSecurityScopedResource()
    }
    return url
  }

  private func describe(_ url: URL) -> [String: Any] {
    ["id": url.path, "name": url.lastPathComponent]
  }

  /// Every file under the folder, a few levels deep and capped; hidden files
  /// and packages are skipped.
  private func list() -> [[String: Any]] {
    guard let root = resolve(), root.startAccessingSecurityScopedResource() else { return [] }
    defer { root.stopAccessingSecurityScopedResource() }
    let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
    guard let walk = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles, .skipsPackageDescendants])
    else { return [] }
    var out: [[String: Any]] = []
    for case let url as URL in walk {
      if out.count >= maxFiles { break }
      let values = try? url.resourceValues(forKeys: Set(keys))
      if values?.isDirectory == true {
        if walk.level > maxDepth { walk.skipDescendants() }
        continue
      }
      let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
      out.append([
        "id": url.path,
        "name": url.lastPathComponent,
        "mime": UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "",
        "size": values?.fileSize ?? 0,
        "modified": Int(modified * 1000),
      ])
    }
    return out
  }

  /// Copies one file of the folder into tmp; the path, or nil. The file
  /// coordinator downloads an iCloud file that is not on the device yet.
  private func copy(path: String) -> String? {
    guard let root = resolve(), path.hasPrefix(root.path),
      root.startAccessingSecurityScopedResource()
    else { return nil }
    defer { root.stopAccessingSecurityScopedResource() }
    let source = URL(fileURLWithPath: path)
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("doc_folder/\(UInt(bitPattern: path.hashValue))", isDirectory: true)
    let target = dir.appendingPathComponent(source.lastPathComponent)
    var copied: String?
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &error) { url in
      do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        // The receiver keeps "Date modified" (project_mtime_preservation).
        if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate
        {
          try? FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: target.path)
        }
        copied = target.path
      } catch {
        copied = nil
      }
    }
    return copied
  }

  private func background(_ result: @escaping FlutterResult, _ work: @escaping () -> Any?) {
    DispatchQueue.global(qos: .userInitiated).async {
      let value = work()
      DispatchQueue.main.async { result(value) }
    }
  }

  private static func topController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
  }
}
