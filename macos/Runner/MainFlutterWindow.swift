import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let folderChannelName = "app.bishare/folder"
  private let clipboardChannelName = "app.bishare/clipboard"
  private let bookmarkKey = "bishare.saveFolderBookmark"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Offline "Nearby" over MultipeerConnectivity (shared with iOS). Add
    // BIShareNearbyPlugin.swift to the macOS Runner target in Xcode for this to
    // compile.
    BIShareNearbyPlugin.register(
      with: flutterViewController.registrar(forPlugin: "BIShareNearbyPlugin"))

    // Save-folder picker with persistent security-scoped bookmarks. Lets the
    // sandboxed app write received files to a user-chosen folder (e.g. the real
    // ~/Downloads) and keep write access across launches. See SaveFolderChannel
    // on the Dart side.
    let channel = FlutterMethodChannel(
      name: folderChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "restore":
        result(self.restoreFolder())
      case "pick":
        self.pickFolder(result)
      case "reveal":
        let path = (call.arguments as? [String: Any])?["path"] as? String
        self.reveal(path: path)
        result(nil)
      case "clear":
        // "Use default" — forget the custom folder so it isn't restored next launch.
        self.clearFolderBookmark()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Image clipboard for Universal Clipboard sync (Flutter's Clipboard API is
    // text-only). See ClipboardImageChannel on the Dart side.
    let clipboardChannel = FlutterMethodChannel(
      name: clipboardChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboardChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "getImage":
        result(self.clipboardImage())
      case "setImage":
        let args = call.arguments as? [String: Any]
        let bytes = (args?["bytes"] as? FlutterStandardTypedData)?.data
        result(self.setClipboardImage(bytes))
      case "changeCount":
        result(NSPasteboard.general.changeCount)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// Read the current pasteboard image as PNG bytes (`{bytes, mime}`), or nil.
  /// Prefers a PNG item as-is; TIFF (the common screenshot/copy flavor) is
  /// re-encoded to PNG so peers get a portable format.
  private func clipboardImage() -> [String: Any]? {
    let pb = NSPasteboard.general
    if let png = pb.data(forType: .png), !png.isEmpty {
      return ["bytes": FlutterStandardTypedData(bytes: png), "mime": "image/png"]
    }
    guard let tiff = pb.data(forType: .tiff),
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]),
          !png.isEmpty else { return nil }
    return ["bytes": FlutterStandardTypedData(bytes: png), "mime": "image/png"]
  }

  /// Put encoded image bytes on the pasteboard. NSImage handles PNG/JPEG/TIFF
  /// decode; writeObjects publishes every flavor pasting apps expect.
  private func setClipboardImage(_ data: Data?) -> Bool {
    guard let data = data, let image = NSImage(data: data) else { return false }
    let pb = NSPasteboard.general
    pb.clearContents()
    return pb.writeObjects([image])
  }

  /// Re-establish access to a previously picked folder from its security-scoped
  /// bookmark. Returns the path and keeps access open for the app's lifetime.
  /// Forget the custom save folder: drop write access and remove the bookmark
  /// so the next launch falls back to the app default (Documents/BIShare).
  private func clearFolderBookmark() {
    var stale = false
    if let data = UserDefaults.standard.data(forKey: bookmarkKey),
       let url = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale) {
      url.stopAccessingSecurityScopedResource()
    }
    UserDefaults.standard.removeObject(forKey: bookmarkKey)
  }

  private func restoreFolder() -> String? {
    guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
    var stale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &stale) else { return nil }
    guard url.startAccessingSecurityScopedResource() else { return nil }
    if stale, let fresh = try? url.bookmarkData(
      options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
      UserDefaults.standard.set(fresh, forKey: bookmarkKey)
    }
    return url.path
  }

  /// Show a folder picker; on success persist a security-scoped bookmark and
  /// return the chosen path (access stays open for the app's lifetime).
  private func pickFolder(_ result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.message = "Choose where BIShare saves received files"
    panel.beginSheetModal(for: self) { [weak self] response in
      guard let self = self, response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      if let data = try? url.bookmarkData(
        options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
        UserDefaults.standard.set(data, forKey: self.bookmarkKey)
      }
      _ = url.startAccessingSecurityScopedResource()
      result(url.path)
    }
  }

  /// Open the folder in Finder so the user can see their received files.
  private func reveal(path: String?) {
    guard let path = path, !path.isEmpty else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: path))
  }
}
