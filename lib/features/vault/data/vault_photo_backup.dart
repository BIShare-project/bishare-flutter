import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
    Future<void> Function()? catchUp,
    Stream<void>? networkChanges,
    Future<List<String>> Function()? exportDirs,
    this.batch = 30,
  }) : _library = library,
       _exportDirs = exportDirs ?? _appTempDirs,
       _dao = dao,
       _uploader = uploader,
       _files = files,
       _keys = keys,
       _prefs = prefs,
       _folderName = folderName,
       _onWifi = onWifi ?? _wifiNow,
       _catchUp = catchUp,
       _networkChanges = networkChanges ?? _connectivityChanges();

  final PhotoLibrary _library;
  final VaultDao _dao;
  final VaultUploader _uploader;
  final VaultFiles _files;
  final VaultKeyStore _keys;
  final SharedPreferences _prefs;
  final String Function() _folderName;
  final Future<bool> Function() _onWifi;

  /// Brings the index up to the server (VaultSync.pull). An upload that just
  /// finished is in the Drive before it is in this device's index; looking
  /// at the library in between would send that photo a second time.
  final Future<void> Function()? _catchUp;
  final Stream<void> _networkChanges;

  /// The app's own temporary folders: the only places a library export is
  /// deleted from (an iOS export, Android's copy), so the photo itself is
  /// never touched.
  final Future<List<String>> Function() _exportDirs;
  List<String>? _dirs;

  /// Rounds in a row whose every photo failed (audit P4): after two, rounds
  /// stop starting each other and wait for the next reason to look (the
  /// library changed, the network came back, the app came back).
  int _stalled = 0;

  /// An upload said this device can no longer send to this Drive: nothing
  /// more is looked at until the next start or the switch turned on again.
  bool _lost = false;

  /// Each photo's failed tries and when it may go again (owner 2026-10-22:
  /// a failed photo was tried without end, or not until something else
  /// started a round). Kept in the index's state table, so it lasts across
  /// starts. After [maxTries] a photo waits for "Try again" ([retryGaveUp]).
  static const _kRetries = 'photoBackupRetries';
  static const maxTries = 5;

  /// The wait after each failed try: the first goes again at once, from a
  /// fresh copy (an export the system cleared).
  static const _waits = [
    Duration.zero,
    Duration(minutes: 5),
    Duration(minutes: 30),
    Duration(hours: 2),
  ];
  Map<String, (int, int)> _retries = {};
  Timer? _retryTimer;

  /// Photos left out after [maxTries] failed tries.
  int get gaveUp => _retries.values.where((r) => r.$1 >= maxTries).length;

  Future<void> _loadRetries() async {
    try {
      final raw = await _dao.stateValue(_kRetries);
      if (raw == null) return;
      _retries = {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          e.key: (
            ((e.value as List)[0] as num).toInt(),
            ((e.value as List)[1] as num).toInt(),
          ),
      };
    } on Object {
      _retries = {};
    }
  }

  Future<void> _saveRetries() => _dao.setStateValue(
    _kRetries,
    jsonEncode({
      for (final e in _retries.entries) e.key: [e.value.$1, e.value.$2],
    }),
  );

  /// The photos left out after [maxTries] go again now.
  Future<void> retryGaveUp() async {
    final ids = {
      for (final e in _retries.entries)
        if (e.value.$1 >= maxTries) e.key,
    };
    if (ids.isEmpty) return;
    _retries.removeWhere((id, _) => ids.contains(id));
    await _saveRetries();
    await _dao.deleteTransfers([
      for (final t in await _dao.watchTransfers().first)
        if (ids.contains(t.assetId) && t.state == 'failed') t.id,
    ]);
    _stalled = 0;
    _lost = false;
    notifyListeners();
    unawaited(scan());
  }

  /// The next look when a photo's wait is over (on screen only).
  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!_started || _until != null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = [
      for (final r in _retries.values)
        if (r.$1 < maxTries && r.$2 > now) r.$2,
    ];
    if (due.isEmpty) return;
    final at = due.reduce(min);
    _retryTimer = Timer(
      Duration(milliseconds: at - now + 500),
      () => unawaited(scan()),
    );
  }

  /// Upload errors that say this device can no longer send to this Drive.
  static const _lostErrors = {
    'VAULT_AUTH',
    'VAULT_NOT_FOUND',
    'VAULT_UNAVAILABLE',
    'VAULT_NOT_SIGNED_IN',
  };

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

  /// What was backed up at the last full count, and now: the photos in the
  /// second and not the first come off [left] until the next count. "Now"
  /// follows the index, so uploads that finish outside a round (the queue
  /// left by an earlier run, the app's own uploader) count too.
  Set<String> _backedAtCount = const {};
  Set<String> _backedNow = const {};
  StreamSubscription<Set<String>>? _backedSub;

  void _followBacked() {
    _backedSub ??= _dao.watchBackedUpAssetIds().listen((ids) {
      _backedNow = ids;
      notifyListeners();
    });
  }

  AppLifecycleListener? _lifecycle;

  /// A full count of what is left at most this often (a library can hold
  /// tens of thousands of photos; a round looks only at what it queues).
  static const _countEvery = Duration(seconds: 60);

  bool get available => _library.available;
  bool get on => _prefs.getBool(_kOn) ?? false;
  bool get wifiOnly => _prefs.getBool(_kWifiOnly) ?? true;
  PhotoAccess get access => _access;
  bool get scanning => _scanning != null;

  /// The Drive refused a photo for lack of room (or it is read-only after a
  /// plan ended): backup waits instead of trying photo after photo. Cleared
  /// by turning backup on again or "Back up now", and at the next start.
  bool get noRoom => _noRoom;
  bool _noRoom = false;

  static const _roomErrors = {'STORAGE_LIMIT_EXCEEDED', 'VAULT_READ_ONLY'};

  /// Photos and videos of the library not in the Drive yet (those on their
  /// way included), as of the last look. Null before the first.
  int? get left {
    final l = _left;
    if (l == null) return null;
    return max(0, l - _backedNow.difference(_backedAtCount).length);
  }

  int? get total => _total;

  PhotoLibrary get library => _library;

  /// The Drive is ready on this device: follow the library and the network,
  /// and back up what is new when the switch is on.
  Future<void> start() async {
    if (_started || !available) return;
    _started = true;
    _lost = false;
    _stalled = 0;
    _uploader.mayStart = _mayStart;
    _followBacked();
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
    _retryTimer?.cancel();
    _retryTimer = null;
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
    await _backedSub?.cancel();
    _backedSub = null;
    _backedAtCount = const {};
    _backedNow = const {};
    notifyListeners();
  }

  /// The account is leaving this device (sign-out, another account): the
  /// switch goes with it, so the next account does not start sending the
  /// whole camera roll by itself (audit P6).
  Future<void> forget() async {
    await stop();
    await _prefs.remove(_kOn);
    _noRoom = false;
    _stalled = 0;
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
    if (value) {
      _noRoom = false;
      _lost = false;
      _stalled = 0;
      _retries = {};
      await _saveRetries();
    }
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
    _noRoom = false;
    await _loadRetries();
    if (assets.any((a) => _retries.containsKey(a.id))) {
      _retries.removeWhere((id, _) => assets.any((a) => a.id == id));
      await _saveRetries();
    }
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
    if (!_started || _lost || _timeUp || await _keys.vaultKey() == null) {
      return;
    }
    await _discardFinished();
    if (_access == PhotoAccess.none) _access = await _library.access();
    if (_access == PhotoAccess.none) return;
    final uploads = await _dao.watchAssetUploads().first;
    var backed = await _dao.backedUpAssetIds();
    bool behind() => uploads.entries.any(
      (e) => e.value == 'done' && !backed.contains(e.key),
    );
    if (behind()) {
      final catchUp = _catchUp;
      try {
        if (catchUp != null) await catchUp();
      } on Object catch (e) {
        debugPrint('[vault] photo backup catch-up: $e');
      }
      backed = await _dao.backedUpAssetIds();
      // Still not in the index: without a way to catch up (or offline), the
      // photo waits a round; with one, it was deleted from the Drive and
      // goes up again (below).
      if (catchUp == null && behind()) {
        backed = {
          ...backed,
          for (final e in uploads.entries)
            if (e.value == 'done') e.key,
        };
      }
    }
    _backedNow = backed;
    // A photo whose upload failed (it was edited, its export went away) is
    // tried again from a fresh copy.
    final failed = [
      for (final t in await _dao.watchTransfers().first)
        if (t.assetId != null && t.state == 'failed') t,
    ];
    if (failed.any((t) => _roomErrors.contains(t.error))) {
      // A full Drive refuses every photo: one try per start is enough.
      if (_noRoom) return;
      _noRoom = true;
      notifyListeners();
    }
    await _loadRetries();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (failed.isNotEmpty) {
      final again = <int>[];
      for (final t in failed) {
        final id = t.assetId!;
        final tries = _retries[id]?.$1 ?? 0;
        // Left out already: its row stays, so its badge says failed.
        if (tries >= maxTries) continue;
        // Not the photo's fault: a full Drive, a device that lost the Drive.
        final counts =
            !_roomErrors.contains(t.error) && !_lostErrors.contains(t.error);
        if (counts && tries + 1 >= maxTries) {
          _retries[id] = (tries + 1, 0);
          continue;
        }
        if (counts) {
          _retries[id] = (tries + 1, nowMs + _waits[tries].inMilliseconds);
        }
        await _discard(t.localPath);
        again.add(t.id);
      }
      await _dao.deleteTransfers(again);
      await _saveRetries();
      notifyListeners();
    }
    // Backed up since: nothing to remember about them.
    if (_retries.keys.any(backed.contains)) {
      _retries.removeWhere((id, _) => backed.contains(id));
      await _saveRetries();
    }

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
        final retry = _retries[a.id];
        final resting =
            retry != null && (retry.$1 >= maxTries || retry.$2 > nowMs);
        if (!busy && !resting && todo.length < batch) todo.add(a);
      }
      if (!counting && todo.length >= batch) break;
    }
    _total = total;
    if (counting) {
      _left = left;
      _countedAt = DateTime.now();
      _backedAtCount = backed;
      _backedNow = backed;
    }
    notifyListeners();
    if (!on || todo.isEmpty) return;
    final queued = await _queue(todo);
    await _tickOff();
    if (queued > 0) {
      await _uploader.run();
      await _tickOff();
      final ids = {for (final a in todo) a.id};
      final mine = [
        for (final t in await _dao.watchTransfers().first)
          if (ids.contains(t.assetId)) t,
      ];
      final failedNow = [
        for (final t in mine)
          if (t.state == 'failed') t,
      ];
      final lost = failedNow.any((t) => _lostErrors.contains(t.error));
      if (lost) _lost = true;
      _stalled = lost || (mine.isNotEmpty && failedNow.length == mine.length)
          ? _stalled + 1
          : 0;
      await _discardFinished();
      // Only when the batch is through: offline, or on mobile data with
      // "Wi-Fi only", the next round waits for the network to say so. Nor
      // after this device lost the Drive, or two rounds that all failed.
      final stuck = (await _dao.pendingTransfers()).any(
        (t) => t.assetId != null,
      );
      if (!stuck && !lost && _stalled < 2) _again = true;
      _scheduleRetry();
    } else if (todo.length == batch) {
      // All of them were already in the Drive: look at the next ones.
      _again = true;
    }
  }

  /// The index as it is now, for [left] (the watch may not have caught up).
  Future<void> _tickOff() async {
    _backedNow = await _dao.backedUpAssetIds();
    notifyListeners();
  }

  /// Queue [assets], marking those already in the Drive. Returns how many
  /// went into the upload queue.
  Future<int> _queue(List<PhotoAsset> assets) async {
    // Made (or found) only when a photo is actually sent.
    String? folder;
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
        await _discard(got.file.path);
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
      folder ??= await _folder();
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

  /// Delete library exports whose upload is over (sent, failed, cancelled),
  /// and photo_manager's own cache once no photo is waiting (audit P3: a
  /// large library filled the phone with exported originals).
  Future<void> _discardFinished() async {
    var waiting = false;
    for (final t in await _dao.watchTransfers().first) {
      if (t.assetId == null) continue;
      if (t.state == 'done' || t.state == 'failed' || t.state == 'cancelled') {
        await _discard(t.localPath);
      } else {
        waiting = true;
      }
    }
    if (!waiting) await _library.clearExports();
  }

  /// [path], when it is an export in the app's own temporary folders.
  Future<void> _discard(String? path) async {
    if (path == null) return;
    try {
      final dirs = _dirs ??= await _exportDirs().catchError(
        (Object _) => const <String>[],
      );
      if (!dirs.any((d) => p.isWithin(d, path))) return;
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on Object catch (e) {
      debugPrint('[vault] photo export not deleted: $e');
    }
  }

  static Future<List<String>> _appTempDirs() async => [
    (await getTemporaryDirectory()).path,
    if (!Platform.isIOS) (await getApplicationCacheDirectory()).path,
  ];

  /// The Drive folder photos go to, made the first time (and again if it was
  /// deleted or trashed).
  Future<String> _folder() async {
    final id = await _dao.stateValue(_kFolder);
    if (id != null) {
      final o = await _dao.object(id);
      if (o != null && o.kind == 'dir' && o.trashedAt == null) return id;
    }
    // A reinstall (or another device) already has it: the same folder, not
    // a second one next to it.
    final name = _folderName();
    for (final o in await _dao.liveChildren(null)) {
      if (o.kind == 'dir' && o.name == name) {
        await _dao.setStateValue(_kFolder, o.id);
        return o.id;
      }
    }
    final made = await _files.mkdir(name);
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
