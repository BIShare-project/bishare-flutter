import 'dart:io';

import '../protocol/file_metadata.dart';
import '../rust/rust_facade.dart';

/// Decides where an incoming file is saved and under what name — parity with the
/// native receiver's `FileCategorizer` + `SmartNaming` (both reused via Rust FFI):
///
/// * Category folder: `Images` / `Videos` / `Documents` / `Archives` / `Other`.
/// * Name: `{yyyy-MM-dd}_{sender}_{name}` (native `SmartNaming`).
///
/// Extra over native: a "junk name" from photo-library senders (e.g. an iOS
/// PHAsset localIdentifier like `AQMBofb1…w6Z0Ir….mp4`) is rewritten to a friendly
/// `Video_20260706_103012_localhost.mp4` instead of keeping the opaque token.
class ReceiveNaming {
  ReceiveNaming._();

  /// Resolve the final save [File] (category subfolder created, name de-duplicated).
  static File targetFile(
    Directory saveDir,
    FileMetadata meta,
    String senderAlias,
  ) {
    final category = Rust.categoryName(meta.fileType); // Images/Videos/…
    final base = Rust.sanitizeFilename(meta.fileName);
    final name = _isJunkName(_stem(base))
        ? _friendlyName(category, _ext(base), senderAlias)
        : Rust.smartName(base, senderAlias);

    final dir = Directory('${saveDir.path}${Platform.pathSeparator}$category');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _deduped(dir, name);
  }

  /// A name is "junk" if its stem is a long, dot-free, base64/hex-ish token with
  /// no human-readable words — i.e. an opaque asset identifier, not a real name.
  static bool _isJunkName(String stem) {
    if (stem.length < 40) return false;
    return RegExp(r'^[A-Za-z0-9_+\-]+$').hasMatch(stem);
  }

  static String _friendlyName(String category, String ext, String sender) {
    final kind = switch (category) {
      'Images' => 'Photo',
      'Videos' => 'Video',
      'Documents' => 'Document',
      'Archives' => 'Archive',
      _ => 'File',
    };
    final safeSender = sender
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[/:\\]'), '_');
    return '${kind}_${_timestamp()}_$safeSender$ext';
  }

  static File _deduped(Directory dir, String name) {
    var candidate = File('${dir.path}${Platform.pathSeparator}$name');
    if (!candidate.existsSync()) return candidate;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    do {
      candidate = File('${dir.path}${Platform.pathSeparator}$stem ($i)$ext');
      i++;
    } while (candidate.existsSync());
    return candidate;
  }

  static String _stem(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  static String _timestamp() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p(n.month)}${p(n.day)}_${p(n.hour)}${p(n.minute)}${p(n.second)}';
  }
}
