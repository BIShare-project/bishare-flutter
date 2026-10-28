import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/app_database.dart';
import '../../history/data/history_repository.dart';

/// Reactive list of received files (drift-backed → survives restart).
class InboxCubit extends Cubit<List<TransferRecord>> {
  InboxCubit(this._history, {SharedPreferences? prefs})
    : _prefs = prefs,
      seenAt = ValueNotifier(
        DateTime.fromMillisecondsSinceEpoch(prefs?.getInt(_kSeenAt) ?? 0),
      ),
      super(const []) {
    _sub = _history.watchReceived().listen(emit);
  }

  final HistoryRepository _history;
  final SharedPreferences? _prefs;
  static const _kSeenAt = 'inbox.seenAt';

  /// When the Inbox was last left: what arrived after it is new (the dot on
  /// a group, the count on the tab).
  final ValueNotifier<DateTime> seenAt;

  /// Received after the last visit.
  int get unseen =>
      state.where((r) => r.timestamp.isAfter(seenAt.value)).length;

  /// Called when the Inbox is left: everything on it now counts as seen.
  void markSeen() {
    final now = DateTime.now();
    seenAt.value = now;
    _prefs?.setInt(_kSeenAt, now.millisecondsSinceEpoch);
  }

  late final StreamSubscription<List<TransferRecord>> _sub;

  /// Save-to-Photos is only supported on mobile (gal). Elsewhere it's hidden.
  static bool get canSaveToPhotos => Platform.isIOS || Platform.isAndroid;

  /// Remove from the inbox and delete the file on disk.
  Future<void> deleteEntry(TransferRecord r) async {
    await _history.delete(r.id);
    await _unlink(r.savedPath);
  }

  /// Delete several records + their files.
  Future<void> deleteMany(Iterable<TransferRecord> records) async {
    for (final r in records) {
      await deleteEntry(r);
    }
  }

  /// Save a received photo/video to the OS gallery (mobile only). Returns false
  /// if unsupported, permission denied, or the file is gone. Never throws.
  Future<bool> saveToPhotos(TransferRecord r) async {
    if (!canSaveToPhotos) return false;
    final path = r.savedPath;
    if (path == null || !File(path).existsSync()) return false;
    try {
      if (!await Gal.requestAccess(toAlbum: true)) return false;
      if ((r.fileType ?? '').startsWith('video/')) {
        await Gal.putVideo(path);
      } else {
        await Gal.putImage(path);
      }
      return true;
    } on Object {
      return false;
    }
  }

  /// Save every image/video record to the gallery; returns the saved count.
  Future<int> saveAllMedia(List<TransferRecord> records) async {
    var saved = 0;
    for (final r in records) {
      final t = r.fileType ?? '';
      if (t.startsWith('image/') || t.startsWith('video/')) {
        if (await saveToPhotos(r)) saved++;
      }
    }
    return saved;
  }

  Future<void> _unlink(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (!f.existsSync()) return;
    try {
      await f.delete();
    } on FileSystemException {
      // best-effort; the record is already gone
    }
  }

  @override
  Future<void> close() async {
    seenAt.dispose();
    await _sub.cancel();
    return super.close();
  }
}
