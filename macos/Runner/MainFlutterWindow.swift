import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let folderChannelName = "app.bishare/folder"
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// Re-establish access to a previously picked folder from its security-scoped
  /// bookmark. Returns the path and keeps access open for the app's lifetime.
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
