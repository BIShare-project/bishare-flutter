import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/storage/app_database.dart';

/// Ring-buffered clipboard history (last [BIShareConfig.clipboardHistoryMax]
/// synced items, plan §1 phase 2) over the drift `ClipboardHistory` table.
/// Image entries keep their bytes as files under [mediaDir]; trimming (and
/// delete/clear) unlinks those files so history can never grow unbounded on
/// disk either.
class ClipboardHistoryStore {
  ClipboardHistoryStore(
    this._db,
    this.mediaDir, {
    this.maxEntries = BIShareConfig.clipboardHistoryMax,
  });

  final AppDatabase _db;

  /// Where image entries' bytes live (e.g. `<app-support>/clipboard`).
  final Directory mediaDir;

  /// Ring-buffer capacity (20 per protocol constant; injectable for tests).
  final int maxEntries;

  final _uuid = const Uuid();

  /// Newest-first history, capped at [maxEntries].
  Stream<List<ClipboardHistoryData>> watch() => _db.watchClipboard(maxEntries);

  /// Record a synced TEXT item (local copy or received from a peer).
  Future<void> addText({
    required String text,
    required String senderAlias,
    String? senderFingerprint,
  }) => _insert(
    ClipboardHistoryCompanion.insert(
      kind: 'text',
      textContent: Value(text),
      senderAlias: senderAlias,
      senderFingerprint: Value(senderFingerprint),
      createdAt: DateTime.now(),
    ),
  );

  /// Record a synced IMAGE item, persisting [bytes] to a file in [mediaDir].
  Future<void> addImage({
    required Uint8List bytes,
    required String mime,
    required String senderAlias,
    String? senderFingerprint,
    String? fileName,
  }) async {
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    final file = File(
      '${mediaDir.path}${Platform.pathSeparator}'
      '${_uuid.v4()}.${_extensionFor(mime)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    await _insert(
      ClipboardHistoryCompanion.insert(
        kind: 'image',
        mime: Value(mime),
        fileName: Value(fileName),
        filePath: Value(file.path),
        senderAlias: senderAlias,
        senderFingerprint: Value(senderFingerprint),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Delete one entry (and its on-disk files).
  Future<void> remove(ClipboardHistoryData entry) async {
    await _db.deleteClipboardEntry(entry.id);
    _unlink(entry);
  }

  /// Clear the whole history (and every on-disk file).
  Future<void> clear() async {
    final all = await _db.allClipboardEntries();
    await _db.clearClipboardHistory();
    all.forEach(_unlink);
  }

  /// Insert then trim to the newest [maxEntries] rows — the ring buffer.
  Future<void> _insert(ClipboardHistoryCompanion row) async {
    await _db.insertClipboardEntry(row);
    final overflow = await _db.clipboardOverflow(maxEntries);
    for (final old in overflow) {
      await _db.deleteClipboardEntry(old.id);
      _unlink(old);
    }
  }

  void _unlink(ClipboardHistoryData entry) {
    for (final path in [entry.filePath, entry.previewPath]) {
      if (path == null || path.isEmpty) continue;
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } on FileSystemException {
        // best-effort — the row is already gone
      }
    }
  }

  static String _extensionFor(String mime) => switch (mime) {
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/tiff' => 'tiff',
    _ => 'png',
  };
}
