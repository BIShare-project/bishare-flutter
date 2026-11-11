import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/android_downloads_channel.dart';
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

  /// [seenAt] is gone: a [markSeen] deferred past a frame must not touch it.
  bool _closing = false;

  /// Received after the last visit.
  int get unseen =>
      state.where((r) => r.timestamp.isAfter(seenAt.value)).length;

  /// Called when the Inbox is left: everything on it now counts as seen.
  void markSeen() {
    final now = DateTime.now();
    _prefs?.setInt(_kSeenAt, now.millisecondsSinceEpoch);
    // Called while the Inbox leaves the screen, which can be in the middle
    // of a build: the tab badge listens, so it hears after the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_closing) seenAt.value = now;
      });
    } else {
      seenAt.value = now;
    }
  }

  late final StreamSubscription<List<TransferRecord>> _sub;

  /// Save-to-Photos is only supported on mobile (gal). Elsewhere it's hidden.
  static bool get canSaveToPhotos => Platform.isIOS || Platform.isAndroid;

  /// Remove from the inbox and delete the file on disk. A Live Photo goes
  /// with its other half (the motion has no tile of its own to delete it).
  Future<void> deleteEntry(TransferRecord r) async {
    await _history.delete(r.id);
    await _unlink(r.savedPath);
    final group = r.liveGroup;
    if (group == null) return;
    for (final x in [...state]) {
      if (x.id != r.id && x.liveGroup == group) {
        await _history.delete(x.id);
        await _unlink(x.savedPath);
      }
    }
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
    // Android: the file is already where it was saved; the gallery indexes
    // it there (a copy would show twice, and lose a Live Photo's pair).
    // A Live Photo's motion goes with its still.
    if (Platform.isAndroid) {
      final partner = livePartner(r)?.savedPath;
      return await AndroidDownloadsPath.scanMedia([path, ?partner]) > 0;
    }
    try {
      if (!await Gal.requestAccess(toAlbum: true)) return false;
      // One half of a Live Photo, with the other half here too: Photos gets
      // them back as one Live Photo (motion and sound).
      final partner = Platform.isIOS ? livePartner(r) : null;
      if (partner != null) {
        if (await _saveLive(r, partner)) return true;
        debugPrint(
          '[Inbox] Live Photo save refused, saving ${r.fileName} alone',
        );
      }
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
  /// On iPhone/iPad a Live Photo's two halves are saved once, together.
  Future<int> saveAllMedia(List<TransferRecord> records) async {
    var saved = 0;
    final liveDone = <String>{};
    for (final r in records) {
      final t = r.fileType ?? '';
      if (t.startsWith('image/') || t.startsWith('video/')) {
        final group = r.liveGroup;
        if (Platform.isIOS && group != null && livePartner(r) != null) {
          if (!liveDone.add(group)) continue;
        }
        if (await saveToPhotos(r)) saved++;
      }
    }
    return saved;
  }

  /// The other half of [r]'s Live Photo, when it was received too.
  TransferRecord? livePartner(TransferRecord r) {
    final group = r.liveGroup;
    if (group == null) return null;
    for (final x in state) {
      if (x.id != r.id &&
          x.liveGroup == group &&
          x.savedPath != null &&
          File(x.savedPath!).existsSync()) {
        return x;
      }
    }
    return null;
  }

  /// Saves the pair as one Live Photo. False when Photos refused it (the
  /// caller then saves [r] on its own).
  Future<bool> _saveLive(TransferRecord r, TransferRecord partner) async {
    final rIsImage = (r.fileType ?? '').startsWith('image/');
    final image = rIsImage ? r : partner;
    final video = rIsImage ? partner : r;
    try {
      await PhotoManager.editor.darwin.saveLivePhoto(
        imageFile: File(image.savedPath!),
        videoFile: File(video.savedPath!),
        title: image.fileName,
      );
      debugPrint('[Inbox] Live Photo saved: ${image.fileName}');
      return true;
    } on PlatformException catch (e) {
      debugPrint('[Inbox] Live Photo save failed: ${e.code} ${e.message}');
      return false;
    } on ArgumentError catch (e) {
      debugPrint('[Inbox] Live Photo save failed: $e');
      return false;
    } on Object catch (e) {
      // Saved, but with add-only access the new asset cannot be read back.
      debugPrint('[Inbox] Live Photo saved (no read-back: $e)');
      return true;
    }
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
    // Android: out of the gallery too.
    unawaited(AndroidDownloadsPath.scanMedia([path]));
  }

  @override
  Future<void> close() async {
    _closing = true;
    seenAt.dispose();
    await _sub.cancel();
    return super.close();
  }
}
