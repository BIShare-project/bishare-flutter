import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/locator.dart';
import '../../../core/protocol/file_metadata.dart';
import '../../../core/server/receive_naming.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/storage/app_database.dart';
import '../data/clipboard_history_store.dart';
import '../data/clipboard_service.dart';

class ClipboardState extends Equatable {
  const ClipboardState({this.entries = const []});

  /// Newest-first synced clipboard items (ring-buffered to 20 by the store).
  final List<ClipboardHistoryData> entries;

  ClipboardState copyWith({List<ClipboardHistoryData>? entries}) =>
      ClipboardState(entries: entries ?? this.entries);

  @override
  List<Object?> get props => [entries];
}

/// Drives the Clipboard history page over [ClipboardHistoryStore]: live list
/// plus the row actions (copy-again / save-to-files / delete / clear).
class ClipboardCubit extends Cubit<ClipboardState> {
  ClipboardCubit(this._store, this._server) : super(const ClipboardState()) {
    _sub = _store.watch().listen(
      (rows) => emit(state.copyWith(entries: rows)),
    );
  }

  final ClipboardHistoryStore _store;
  final TransferServer _server;
  late final StreamSubscription<List<ClipboardHistoryData>> _sub;

  /// Resolved lazily (the DI singleton) so re-copy can prime the sync poll's
  /// echo guards — otherwise a copy-again re-enters the poll loop and duplicates
  /// the row + on-disk file.
  ClipboardService get _clipboard => getIt<ClipboardService>();

  /// Put [entry] back on the system clipboard. Returns false when the item
  /// can't be copied (image file gone / platform without image clipboard).
  /// Goes through [ClipboardService] so the sync poll treats the re-copy as
  /// already-seen (no duplicate broadcast / history row).
  Future<bool> copyAgain(ClipboardHistoryData entry) async {
    if (entry.kind == 'image') {
      final path = entry.filePath;
      if (path == null || !File(path).existsSync()) return false;
      return _clipboard.markLocalCopyImage(
        await File(path).readAsBytes(),
        entry.mime ?? 'image/png',
      );
    }
    final text = entry.textContent;
    if (text == null || text.isEmpty) return false;
    _clipboard.markLocalCopy(text); // arm the guard BEFORE writing
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  /// Save an image entry into the received-files folder (same smart naming as
  /// a received file). Returns the saved path, or null on failure.
  Future<String?> saveToFiles(ClipboardHistoryData entry) async {
    final path = entry.filePath;
    if (path == null || !File(path).existsSync()) return null;
    final src = File(path);
    final meta = FileMetadata(
      id: '${entry.id}',
      fileName: entry.fileName ?? _defaultName(entry),
      size: src.lengthSync(),
      fileType: entry.mime ?? 'image/png',
    );
    try {
      final target = ReceiveNaming.targetFile(
        _server.saveDirectory,
        meta,
        entry.senderAlias,
      );
      await src.copy(target.path);
      return target.path;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> remove(ClipboardHistoryData entry) => _store.remove(entry);

  Future<void> clearAll() => _store.clear();

  static String _defaultName(ClipboardHistoryData entry) {
    final ext = switch (entry.mime) {
      'image/jpeg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => 'png',
    };
    return 'Clipboard-${entry.id}.$ext';
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
