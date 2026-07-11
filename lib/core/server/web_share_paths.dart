import 'dart:io';

import 'package:path/path.dart' as p;

/// Path validation for the browser Web-Share endpoints that accept a
/// caller-supplied relative path (`/api/v1/browse`, `/download-folder`,
/// `/api/v1/download-file`). Browsers are untrusted input: every path is
/// rejected unless it provably stays inside the share root (the receiver's
/// save directory).
class WebSharePaths {
  WebSharePaths._();

  /// Resolves browser-supplied [rel] against [root] and returns the absolute
  /// path, or null when the path must be rejected:
  ///
  /// * absolute paths (`/etc/passwd`, `C:\x`, `\\server\share`),
  /// * traversal or self segments (`..`, `.`),
  /// * backslashes and NUL (never produced by our own listing, only attacks),
  /// * hidden segments (`.foo`) — dotfiles and `.part`/`.browser-*` temps in
  ///   the save dir are private to the app.
  ///
  /// An empty [rel] resolves to the root itself. The check is purely lexical;
  /// callers serving an existing path should additionally pass its symlink
  /// resolution through [contains].
  static String? resolveUnder(Directory root, String rel) {
    if (rel.contains('\u0000') || rel.contains('\\')) return null;
    if (rel.startsWith('/')) return null;
    // Windows drive-letter absolutes ("C:...") — and on Windows hosts a colon
    // anywhere also risks NTFS alternate data streams.
    if (RegExp(r'^[A-Za-z]:').hasMatch(rel)) return null;
    if (Platform.isWindows && rel.contains(':')) return null;
    final segments = rel.split('/').where((s) => s.isNotEmpty).toList();
    for (final s in segments) {
      if (s == '.' || s == '..' || s.startsWith('.')) return null;
    }
    final rootPath = p.normalize(root.absolute.path);
    final resolved = p.normalize(p.joinAll([rootPath, ...segments]));
    if (!p.equals(resolved, rootPath) && !p.isWithin(rootPath, resolved)) {
      return null;
    }
    return resolved;
  }

  /// Whether [path] (typically a symlink-resolved one) is [root] or inside it.
  static bool contains(Directory root, String path) {
    final rootPath = p.normalize(root.absolute.path);
    return p.equals(path, rootPath) || p.isWithin(rootPath, path);
  }
}
