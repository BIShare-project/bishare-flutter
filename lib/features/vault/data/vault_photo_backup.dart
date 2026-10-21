import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_file_work.dart';
import 'vault_files.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';
import 'vault_photo_library.dart';
import 'vault_uploader.dart';

/// Where one photo or video of the library stands, for the badge on it.
enum PhotoBackupState { notBackedUp, waiting, uploading, backedUp, failed }

/// Photo backup (drive-plan.md tasks 5.2, 5.3, 5.8): the camera roll goes up
/// to the Drive once, into one folder, newest first.
///
/// - A photo whose content is already in the Drive (the same SHA-256 in the
///   index, from any device) is marked backed up and not sent again.
/// - With "Wi-Fi only" (the default) the uploads it adds wait while the
///   phone is on mobile data; "Back up now" on chosen photos does not wait.
/// - It works in small batches: a phone with 20,000 photos does not export
///   and hash them all before the first one goes up.
/// - A photo deleted from the Drive (or left in its trash) counts as not
///   backed up and goes up again.
class VaultPhotoBackup extends ChangeNotifier {
  VaultPhotoBackup({
    required PhotoLibrary library,
    required VaultDao dao,
    required VaultUploader uploader,
    required VaultFiles files,
    required VaultKeyStore keys,
    required SharedPreferences prefs,
    required String Function() folderName,
    Future<bool> Function()? onWifi,
    Stream<void>? networkChanges,
    this.batch = 30,
  }) : _library = library,
       _dao = dao,
       _uploader = uploader,
       _files = files,
       _keys = keys,
       _prefs = prefs,
       _folderName = folderName,
       _onWifi = onWifi ?? _wifiNow,
       _networkChanges = networkChanges ?? _connectivityChanges();

  final PhotoLibrary _library;
  final VaultDao _dao;
  final VaultUploader _uploader;
  final VaultFiles _files;
  final VaultKeyStore _keys;
  final SharedPreferences _prefs;
  final String Function() _folderName;
  final Future<bool> Function() _onWifi;
  final Stream<void> _networkChanges;

  /// Photos looked at (exported, hashed, queued) per round.
  final int batch;

  static const _kOn = 'vault.photoBackup';
  static const _kWifiOnly = 'vault.photoBackupWifiOnly';
  static const _kFolder = 'photoBackupFolder';

  /// Chosen with "Back up now": these go up on mobile data too.
  final Set<String> _now = {};
  final List<StreamSubscription<void>> _subs = [];
  bool _started = false;
  Future<void>? _scanning;
  bool _again = false;

  PhotoAccess _access = PhotoAccess.none;
  int? _left;
  int? _total;
  DateTime? _countedAt;

  /// The end of a background run's time: nothing new is looked at after it.
  DateTime? _until;

  bool get _timeUp {
    final until = _until;
    return until != null && DateTime.now().isAfter(until);
  }

  /// Backed up since the last full count (taken off [left] until the next).
  final Set<String> _doneSinceCount = {};
  AppLifecycleListener? _lifecycle;

  /// A full count of what is left at most this often (a library can hold
  /// tens of thousands of photos; a round looks only at what it queues).
  static const _countEvery = Duration(seconds: 60);

  bool get available => _library.available;
  bool get on => _prefs.getBool(_kOn) ?? false;
  bool get wifiOnly => _prefs.getBool(_kWifiOnly) ?? true;
  PhotoAccess get access => _access;
  bool get scanning => _scanning != null;

  /// Photos and videos of the library not in the Drive yet (those on their
  /// way included), as of the last look. Null before the first.
  int? get left {
    final l = _left;
    return l == null ? null : max(0, l - _doneSinceCount.length);
  }

  int? get total => _total;

  PhotoLibrary get library => _library;

  /// The Drive is ready on this device: follow the library and the network,
  /// and back up what is new when the switch is on.
  Future<void> start() async {
    if (_started || !available) return;
    _started = true;
    _uploader.mayStart = _mayStart;
    _access = await _library.access();
    notifyListeners();
    _subs
      ..add(_library.changes.listen((_) => unawaited(scan())))
      ..add(
        _networkChanges.listen((_) async {
          if (!await _onWifi()) return;
          unawaited(_uploader.run());
          unawaited(scan());
        }),
      );
    // Back in the app: what was taken meanwhile.
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(scan()));
    unawaited(scan());
  }

  /// Photo backup's background run (task 5.4): one look at the library and
  /// the uploads it makes, for at most [budget], without the listeners of
  /// [start] (there is no screen and no network watch). Uploads cut by the
  /// end of [budget] go on from where they stopped next time.
  Future<void> runInBackground(Duration budget) async {
    if (!available || !on) return;
    _started = true;
    _uploader.mayStart = _mayStart;
    _until = DateTime.now().add(budget);
    final timeUp = Timer(budget, () => unawaited(_uploader.hold()));
    try {
      _access = await _library.access();
      if (_access == PhotoAccess.none) return;
      // What was queued before (by the app, or the last run) goes first.
      await _uploader.run();
      await scan();
    } finally {
      timeUp.cancel();
      await _uploader.hold();
      _until = null;
      _started = false;
      _uploader.mayStart = null;
    }
  }

  /// Sign-out: nothing more is looked at or queued.
  Future<void> stop() async {
    _started = false;
    _uploader.mayStart = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _lifecycle?.dispose();
    _lifecycle = null;
    _now.clear();
    _left = null;
    _total = null;
    _doneSinceCount.clear();
    notifyListeners();
  }

  /// Turn backup on (asking for the library first) or off. False when the
  /// library cannot be read: the switch stays off and the screen says why.
  Future<bool> setOn(bool value) async {
    if (value) {
      _access = await _library.access(ask: true);
      notifyListeners();
      if (_access == PhotoAccess.none) return false;
    }
    await _prefs.setBool(_kOn, value);
    notifyListeners();
    if (value) unawaited(scan());
    return true;
  }

  Future<void> setWifiOnly(bool value) async {
    await _prefs.setBool(_kWifiOnly, value);
    notifyListeners();
    unawaited(_uploader.run());
  }

  /// Ask for the library again (after the settings were changed).
  Future<void> refreshAccess({bool ask = false}) async {
    _access = await _library.access(ask: ask);
    notifyListeners();
    if (_access != PhotoAccess.none) unawaited(scan());
  }

  Future<bool> _mayStart(VaultTransfer t) async {
    final asset = t.assetId;
    if (asset == null || !wifiOnly || _now.contains(asset)) return true;
    return _onWifi();
  }

  /// [assets] up now, whatever the switch and the network say. One already
  /// in the queue (waiting for Wi-Fi) is let through, not queued twice; one
  /// whose upload failed or was cancelled is queued again.
  Future<void> backUp(List<PhotoAsset> assets) async {
    if (assets.isEmpty) return;
    _now.addAll(assets.map((a) => a.id));
    final uploads = await _dao.watchAssetUploads().first;
    await _queue([
      for (final a in assets)
        if (!_inQueue(uploads[a.id])) a,
    ]);
    unawaited(_uploader.run());
  }

  static bool _inQueue(String? state) =>
      state != null &&
      state != 'done' &&
      state != 'failed' &&
      state != 'cancelled';

  /// Look at the library and queue what is not in the Drive yet. Calls made
  /// while it runs join it, and one more round follows.
  Future<void> scan() {
    final running = _scanning;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _scanLoop().whenComplete(() {
      _scanning = null;
      notifyListeners();
    });
    _scanning = run;
    notifyListeners();
    return run;
  }

  Future<void> _scanLoop() async {
    do {
      _again = false;
      try {
        await _scanOnce();
      } on Object catch (e) {
        debugPrint('[vault] photo backup: $e');
      }
    } while (_again && _started);
  }

  Future<void> _scanOnce() async {
    if (!_started || _timeUp || await _keys.vaultKey() == null) return;
    if (_access == PhotoAccess.none) _access = await _library.access();
    if (_access == PhotoAccess.none) return;
    final backed = await _dao.backedUpAssetIds();
    final uploads = await _dao.watchAssetUploads().first;
    // A photo whose upload failed (it was edited, its export went away) is
    // tried again from a fresh copy.
    final failed = [
      for (final t in await _dao.watchTransfers().first)
        if (t.assetId != null && t.state == 'failed') t.id,
    ];
    if (failed.isNotEmpty) await _dao.deleteTransfers(failed);

    final total = await _library.count();
    final counting =
        _left == null ||
        _countedAt == null ||
        DateTime.now().difference(_countedAt!) > _countEvery;
    final todo = <PhotoAsset>[];
    var left = 0;
    for (var page = 0; page * 500 < total; page++) {
      final assets = await _library.page(page, 500);
      if (assets.isEmpty) break;
      for (final a in assets) {
        if (backed.contains(a.id)) continue;
        left++;
        final state = uploads[a.id];
        final busy = state != null && state != 'failed' && state != 'done';
        if (!busy && todo.length < batch) todo.add(a);
      }
      if (!counting && todo.length >= batch) break;
    }
    _total = total;
    if (counting) {
      _left = left;
      _countedAt = DateTime.now();
      _doneSinceCount.clear();
    }
    notifyListeners();
    if (!on || todo.isEmpty) return;
    final queued = await _queue(todo);
    await _tickOff(todo);
    if (queued > 0) {
      await _uploader.run();
      await _tickOff(todo);
      // Only when the batch is through: offline, or on mobile data with
      // "Wi-Fi only", the next round waits for the network to say so.
      final stuck = (await _dao.pendingTransfers()).any(
        (t) => t.assetId != null,
      );
      if (!stuck) _again = true;
    } else if (todo.length == batch) {
      // All of them were already in the Drive: look at the next ones.
      _again = true;
    }
  }

  /// Those of [batch] in the Drive now come off [left].
  Future<void> _tickOff(List<PhotoAsset> batch) async {
    final backed = await _dao.backedUpAssetIds();
    final before = _doneSinceCount.length;
    _doneSinceCount.addAll([
      for (final a in batch)
        if (backed.contains(a.id)) a.id,
    ]);
    if (_doneSinceCount.length != before) notifyListeners();
  }

  /// Queue [assets], marking those already in the Drive. Returns how many
  /// went into the upload queue.
  Future<int> _queue(List<PhotoAsset> assets) async {
    final folder = await _folder();
    var queued = 0;
    for (final a in assets) {
      if (_timeUp) break;
      final got = await _library.original(a);
      if (got == null) continue;
      final snap = await VaultFileWork.snapshot(got.file.path);
      final hash = VaultMetaCodec.b64u(snap.hash);
      final there = await _dao.liveFileWithHash(hash);
      if (there != null) {
        await _dao.markAssetBackedUp(a.id, hash, there.id);
        continue;
      }
      // An iOS export is a fresh file: give it the time the photo was
      // taken, which Drive keeps as the file's date.
      if (Platform.isIOS) {
        try {
          await got.file.setLastModified(a.taken);
        } on Object {
          // The export's own time, then.
        }
      }
      await _uploader.enqueueAsset(
        got.file,
        assetId: a.id,
        name: got.name,
        parent: folder,
      );
      queued++;
    }
    return queued;
  }

  /// The Drive folder photos go to, made the first time (and again if it was
  /// deleted or trashed).
  Future<String> _folder() async {
    final id = await _dao.stateValue(_kFolder);
    if (id != null) {
      final o = await _dao.object(id);
      if (o != null && o.kind == 'dir' && o.trashedAt == null) return id;
    }
    final made = await _files.mkdir(_folderName());
    await _dao.setStateValue(_kFolder, made);
    return made;
  }

  /// The state of each asset of [ids], for the badges: from what is in the
  /// Drive and what is in the upload queue.
  static PhotoBackupState stateOf(
    String id,
    Set<String> backed,
    Map<String, String> uploads,
  ) {
    if (backed.contains(id)) return PhotoBackupState.backedUp;
    return switch (uploads[id]) {
      null || 'done' || 'cancelled' => PhotoBackupState.notBackedUp,
      'failed' => PhotoBackupState.failed,
      'queued' => PhotoBackupState.waiting,
      _ => PhotoBackupState.uploading,
    };
  }

  static Future<bool> _wifiNow() async {
    final now = await Connectivity().checkConnectivity();
    return now.contains(ConnectivityResult.wifi) ||
        now.contains(ConnectivityResult.ethernet);
  }

  static Stream<void> _connectivityChanges() =>
      Connectivity().onConnectivityChanged.map((_) {});

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
