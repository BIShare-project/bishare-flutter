import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Cross-platform "where do received files go" folder selection.
///
/// * **macOS** (sandboxed): a native channel shows an NSOpenPanel and persists a
///   security-scoped bookmark, so write access to the chosen folder survives app
///   restarts. [restore] re-establishes that access at startup.
/// * **Windows / Linux** (no sandbox): file_picker's directory picker; the plain
///   path persists directly.
/// * **iOS / Android**: not offered — the app saves to its Documents dir.
class SaveFolderChannel {
  const SaveFolderChannel._();

  static const _channel = MethodChannel('app.bishare/folder');

  /// Whether a custom save folder can be chosen on this platform.
  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// The received-files directory for a user-CHOSEN base folder: always a
  /// `BIShare/` subfolder of it, created if missing. Received files never land
  /// loose in the picked folder (e.g. straight onto the Desktop) — the picked
  /// location is treated as a base, exactly like the default/Android/iOS paths.
  /// Returns the base itself if the `BIShare/` subfolder can't be created (e.g.
  /// a permission edge) so a save target always exists.
  static Directory bishareSubdir(String basePath) {
    final dir = Directory('$basePath${Platform.pathSeparator}BIShare');
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } on FileSystemException {
      return Directory(basePath);
    }
  }

  /// Re-open a previously chosen folder from its macOS security-scoped bookmark,
  /// granting write access for this app session. Returns the path, or null if
  /// none was set or it no longer resolves.
  static Future<String?> restore() async {
    if (!Platform.isMacOS) return null;
    try {
      final path = await _channel.invokeMethod<String>('restore');
      return (path != null && path.isNotEmpty) ? path : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Prompt the user to pick a folder. Returns the chosen path, or null if
  /// cancelled/unsupported. On macOS a security-scoped bookmark is persisted.
  static Future<String?> pick() async {
    if (Platform.isMacOS) {
      try {
        final path = await _channel.invokeMethod<String>('pick');
        return (path != null && path.isNotEmpty) ? path : null;
      } on PlatformException {
        return null;
      } on MissingPluginException {
        return null;
      }
    }
    if (Platform.isWindows || Platform.isLinux) {
      return FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose where BIShare saves received files',
      );
    }
    return null;
  }

  /// Forget a previously-picked custom folder (macOS: drop the security-scoped
  /// bookmark) so "Use default" actually sticks across restarts. No-op elsewhere.
  static Future<void> clear() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod('clear');
    } on PlatformException {
      // best-effort
    } on MissingPluginException {
      // best-effort
    }
  }

  /// Open [path] in the system file browser (Finder / Explorer / Files).
  static Future<void> reveal(String path) async {
    if (path.isEmpty) return;
    if (Platform.isMacOS) {
      try {
        await _channel.invokeMethod('reveal', {'path': path});
        return;
      } on PlatformException {
        // fall through to url_launcher
      } on MissingPluginException {
        // fall through to url_launcher
      }
    }
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
