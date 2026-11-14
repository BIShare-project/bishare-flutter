import 'dart:io';

import '../protocol/file_metadata.dart';
import '../rust/rust_facade.dart';
import 'receive_folders.dart';

/// Decides where an incoming file is saved and under what name — parity with the
/// native receiver's `FileCategorizer` + `SmartNaming` (both reused via Rust FFI):
///
/// * Category folder: `Images` / `Videos` / `Documents` / `Archives` / `Other`.
/// * Name: the sender's own file name, as it was on the sending device. With
///   [targetFile]'s `addSender` (the "Add date and sender to file names"
///   setting), `{yyyy-MM-dd}_{sender}_{name}` (native `SmartNaming`).
/// * A name already taken in the folder becomes `name (1).ext`, `name (2).ext`…
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
    String senderAlias, {
    bool addSender = false,
    bool replace = false,
    Set<String>? claimed,
  }) {
    final base = unwrapPhotoExport(Rust.sanitizeFilename(meta.fileName));
    // Images/Videos/…, or the folder the person chose for the type, or the
    // save folder itself when sorting by type is off (ReceiveFolders).
    final category = ReceiveFolders.categoryOf(base, meta.fileType);
    final name = _isJunkName(_stem(base))
        ? _friendlyName(category, _ext(base), senderAlias)
        : addSender
        ? Rust.smartName(base, senderAlias)
        : base;

    final dir = ReceiveFolders.dirFor(saveDir, base, meta.fileType);
    return replace ? _replacing(dir, name, claimed) : _deduped(dir, name);
  }

  /// Whether [meta] would land on a file that is already there (the accept
  /// prompt's "N files already exist").
  static bool clashes(
    Directory saveDir,
    FileMetadata meta,
    String senderAlias, {
    bool addSender = false,
  }) {
    final base = unwrapPhotoExport(Rust.sanitizeFilename(meta.fileName));
    if (_isJunkName(_stem(base))) return false; // always a fresh name
    final name = addSender ? Rust.smartName(base, senderAlias) : base;
    final dir = ReceiveFolders.dirFor(saveDir, base, meta.fileType);
    return File('${dir.path}${Platform.pathSeparator}$name').existsSync();
  }

  /// The plain name, over a file already there. A file of the same name from
  /// the same transfer ([claimed]: paths this session already wrote), or one
  /// being moved into place right now, is not replaced: that one gets ` (1)`.
  static File _replacing(Directory dir, String name, Set<String>? claimed) {
    final candidate = File('${dir.path}${Platform.pathSeparator}$name');
    final key = candidate.path.toLowerCase();
    final at = _handedOut[key];
    final moving = at != null && DateTime.now().difference(at) < _replaceGuard;
    if (moving || (claimed?.contains(key) ?? false)) {
      final other = _deduped(dir, name);
      claimed?.add(other.path.toLowerCase());
      return other;
    }
    _handedOut[key] = DateTime.now();
    claimed?.add(key);
    return candidate;
  }

  /// How long a name just handed out counts as "being moved into place".
  static const _replaceGuard = Duration(seconds: 2);

  /// iOS senders before 2.8.2 sent the photo library's export file name,
  /// `<asset id>_<time>[_o]_<name>` (photo_manager), e.g.
  /// `6E5438ED-9A8C-4ED0-9DEA-AB2D8F8A9360_L0_001_1762851000.123456_o_IMG_4821.HEIC`.
  /// Keep only the photo's own name, IMG_4821.HEIC.
  static final _photoExport = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
    r'[0-9A-Fa-f]{12}(?:_L\d+_\d+)?_\d+(?:\.\d+)?(?:_o)?_(.+)$',
  );

  static String unwrapPhotoExport(String name) {
    final m = _photoExport.firstMatch(name);
    final inner = m?.group(1);
    return inner == null || inner.isEmpty ? name : inner;
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
      'Apps' => 'App',
      _ => 'File',
    };
    final safeSender = sender
        .replaceAll(' ', '-')
        .replaceAll(RegExp(r'[/:\\]'), '_');
    return '${kind}_${_timestamp()}_$safeSender$ext';
  }

  /// Paths handed out but maybe not on disk yet. Files arrive several at a
  /// time (concurrent QUIC files), and each caller moves its file into place
  /// only after an await, so two files of the same name could both see the
  /// name free and the second would overwrite the first. A name stays taken
  /// here until its file has surely been written (the move starts right after
  /// [targetFile] returns, and a copy creates the file at once).
  static final Map<String, DateTime> _handedOut = {};
  static const _holdFor = Duration(seconds: 30);

  static bool _taken(File f) =>
      _handedOut.containsKey(f.path.toLowerCase()) || f.existsSync();

  static File _deduped(Directory dir, String name) {
    final now = DateTime.now();
    _handedOut.removeWhere((_, at) => now.difference(at) > _holdFor);
    var candidate = File('${dir.path}${Platform.pathSeparator}$name');
    if (_taken(candidate)) {
      final dot = name.lastIndexOf('.');
      final stem = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      var i = 1;
      do {
        candidate = File('${dir.path}${Platform.pathSeparator}$stem ($i)$ext');
        i++;
      } while (_taken(candidate));
    }
    _handedOut[candidate.path.toLowerCase()] = now;
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
