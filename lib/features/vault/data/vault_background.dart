import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/app_database.dart';
import 'vault_api.dart';
import 'vault_files.dart';
import 'vault_keys.dart';
import 'vault_photo_backup.dart';
import 'vault_photo_library.dart';
import 'vault_sync.dart';
import 'vault_thumbs.dart';
import 'vault_upload_notice.dart';
import 'vault_uploader.dart';

/// Photo backup while the app is closed (drive-plan.md task 5.4), within
/// what each system allows: on Android a WorkManager job about every hour
/// (on Wi-Fi only when "Wi-Fi only" is on, never on a low battery), each
/// run up to nine minutes; on iOS a background processing task, whenever
/// iOS grants one (often at night on the charger), each run up to three
/// minutes. An upload cut short goes on from where it stopped.
///
/// The app and a background run never send at the same time. A run first
/// asks the app (through [IsolateNameServer]: same process, another
/// isolate) and, when the app answers, leaves the work to it. While a run
/// is sending, the app's uploader asks it to stop before it starts itself
/// ([takeOver]).
class VaultBackground {
  VaultBackground._();

  /// The task's name on both systems; on iOS also the BGTaskScheduler
  /// identifier in Info.plist and AppDelegate.
  static const task = 'app.bishare.vault.backup';

  /// The folder name photo backup makes when the run has no translations.
  static const folderNameKey = 'vault.photoBackupFolderName';

  @visibleForTesting
  static const appPort = 'bishare.vault.app';
  @visibleForTesting
  static const runPort = 'bishare.vault.run';

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Duration get _budget =>
      Platform.isIOS ? const Duration(minutes: 3) : const Duration(minutes: 9);

  static ReceivePort? _app;

  /// The app's side, once at start: background runs can be scheduled, and a
  /// run that starts while the app is up hands its work to [onBackup].
  static Future<void> initialize({
    required Future<void> Function() onBackup,
  }) async {
    if (!supported) return;
    listen(onBackup: onBackup);
    try {
      await Workmanager().initialize(vaultBackgroundDispatcher);
    } on Object catch (e) {
      debugPrint('[vault] background tasks unavailable: $e');
    }
  }

  /// (Again) the port a run looks for. Called at start and whenever the app
  /// comes back to the front: a run that found the app frozen may have taken
  /// the name over.
  static void listen({required Future<void> Function() onBackup}) {
    if (!supported) return;
    _app?.close();
    final port = ReceivePort();
    IsolateNameServer.removePortNameMapping(appPort);
    IsolateNameServer.registerPortWithName(port.sendPort, appPort);
    port.listen((m) {
      if (m is! List || m.length != 2 || m[1] is! SendPort) return;
      final reply = m[1] as SendPort;
      switch (m[0]) {
        case 'ping':
          reply.send('pong');
        // Answered once the work is done: the run that asked keeps the
        // process awake meanwhile (audit P9: answered at once, the system
        // froze the app before anything went).
        case 'backup':
          unawaited(
            onBackup()
                .catchError((Object e) => debugPrint('[vault] backup: $e'))
                .whenComplete(() => reply.send('ok')),
          );
      }
    });
    _app = port;
  }

  /// Follow the switch: a run about every hour while backup is on, none
  /// while it is off.
  static Future<void> schedule({
    required bool on,
    required bool wifiOnly,
  }) async {
    if (!supported) return;
    try {
      if (!on) {
        await Workmanager().cancelByUniqueName(task);
        return;
      }
      if (Platform.isAndroid) {
        await Workmanager().registerPeriodicTask(
          task,
          task,
          frequency: const Duration(hours: 1),
          constraints: Constraints(
            networkType: wifiOnly
                ? NetworkType.unmetered
                : NetworkType.connected,
            requiresBatteryNotLow: true,
          ),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        );
      } else {
        await Workmanager().registerProcessingTask(
          task,
          task,
          initialDelay: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
        );
      }
    } on Object catch (e) {
      debugPrint('[vault] background schedule: $e');
    }
  }

  /// The app is about to send: a background run that is sending stops
  /// first. Returns at once when none is running.
  static Future<void> takeOver({
    @visibleForTesting Duration wait = const Duration(seconds: 20),
  }) async {
    final run = IsolateNameServer.lookupPortByName(runPort);
    if (run == null) return;
    final answer = await _ask(run, 'stop', wait);
    // No answer: the run is gone without unregistering.
    if (answer == null) IsolateNameServer.removePortNameMapping(runPort);
  }

  static Future<Object?> _ask(SendPort to, String what, Duration wait) async {
    final reply = ReceivePort();
    try {
      to.send([what, reply.sendPort]);
      return await reply.first.timeout(wait);
    } on TimeoutException {
      return null;
    } finally {
      reply.close();
    }
  }

  /// One background run. Returns true unless the run should be retried.
  static Future<bool> run({
    Future<bool> Function()? onWifi,
    PhotoLibrary? library,
  }) async {
    // The app is up and answering: it does the work, at no cost here.
    final app = IsolateNameServer.lookupPortByName(appPort);
    if (app != null &&
        await _ask(app, 'ping', const Duration(seconds: 2)) == 'pong') {
      await _ask(app, 'backup', _budget);
      if (Platform.isIOS) await _again();
      return true;
    }

    await Rust.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    final keys = VaultKeyStore();
    final vaultId = await keys.vaultId();
    if (vaultId == null || await keys.vaultKey() == null) {
      return true;
    }
    final api = VaultApi(keys);
    // Still a device of an open Drive: the flag on, this device not removed,
    // the account there (audit P4). Else nothing is sent and the job stops
    // until the app schedules it again.
    try {
      await api.info(vaultId);
    } on VaultApiException catch (e) {
      const gone = {'VAULT_UNAVAILABLE', 'VAULT_NOT_FOUND', 'VAULT_AUTH'};
      if (gone.contains(e.code)) await schedule(on: false, wifiOnly: true);
      return true;
    }
    final db = AppDatabase();
    final sync = VaultSync(api: api, keys: keys, dao: db.vaultDao);
    final thumbs = VaultThumbs(api: api, keys: keys, dao: db.vaultDao);
    final uploader = VaultUploader(
      api: api,
      keys: keys,
      dao: db.vaultDao,
      sync: sync,
      thumbs: thumbs,
    );
    final backup = VaultPhotoBackup(
      library: library ?? DevicePhotoLibrary(),
      dao: db.vaultDao,
      uploader: uploader,
      files: VaultFiles(api: api, keys: keys, dao: db.vaultDao, sync: sync),
      keys: keys,
      prefs: prefs,
      folderName: () => prefs.getString(folderNameKey) ?? 'Camera',
      onWifi: onWifi,
      networkChanges: const Stream.empty(),
      catchUp: sync.pull,
    );

    // The app opening meanwhile asks this run to stop.
    final me = ReceivePort();
    IsolateNameServer.removePortNameMapping(runPort);
    IsolateNameServer.registerPortWithName(me.sendPort, runPort);
    me.listen((m) async {
      if (m is List && m.length == 2 && m[1] is SendPort && m[0] == 'stop') {
        await uploader.hold();
        (m[1] as SendPort).send('stopped');
      }
    });
    _stop = uploader.hold;
    final notice = VaultUploadNotice(
      dao: db.vaultDao,
      uploader: uploader,
      prefs: prefs,
      initialize: true,
    );
    await notice.start();
    try {
      // The index as the server has it: what other devices backed up is
      // not sent again.
      try {
        await sync.pull();
      } on Object catch (e) {
        debugPrint('[vault] background pull: $e');
      }
      await backup.runInBackground(_budget);
      // iOS runs a processing task once: the next one is asked for here
      // (audit P9: it was asked for only when the app started).
      if (Platform.isIOS) await _again();
      return true;
    } finally {
      await notice.stop(summary: true);
      _stop = null;
      IsolateNameServer.removePortNameMapping(runPort);
      me.close();
      await db.close();
    }
  }

  static Future<void> _again() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('vault.photoBackup') != true) return;
    await schedule(
      on: true,
      wifiOnly: prefs.getBool('vault.photoBackupWifiOnly') ?? true,
    );
  }

  static const _time = MethodChannel('app.bishare/background');

  /// iOS: keep [path] (a folder) out of iCloud backups.
  static Future<void> excludeFromBackup(String path) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _time.invokeMethod<void>('excludeFromBackup', {'path': path});
    } on Object catch (e) {
      debugPrint('[vault] backup exclusion: $e');
    }
  }

  /// iOS: ask for the minute or so iOS gives an app that leaves the screen
  /// while a file is going up, and give it back when the queue is done.
  static Future<void> extraTime(bool on) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _time.invokeMethod<void>(on ? 'begin' : 'end');
    } on Object catch (e) {
      debugPrint('[vault] background time: $e');
    }
  }

  /// The app's isolate, with translations loaded: the words a background
  /// run needs and cannot translate itself (the backup folder's name, the
  /// upload notification).
  static Future<void> saveTexts(SharedPreferences prefs) async {
    final folder = 'vault.backup_folder'.tr();
    if (folder == 'vault.backup_folder') return; // not loaded yet
    await prefs.setString(folderNameKey, folder);
    await VaultUploadNotice.saveTexts(prefs);
  }

  /// The system stops the run early (Android).
  static Future<void> Function()? _stop;
}

/// The background isolate's entry point (Workmanager).
@pragma('vm:entry-point')
void vaultBackgroundDispatcher() {
  Workmanager().executeTask(
    (task, _) async {
      if (task != VaultBackground.task) return true;
      try {
        return await VaultBackground.run();
      } on Object catch (e) {
        debugPrint('[vault] background run: $e');
        return true;
      }
    },
    onTaskStopped: (_, _) async {
      await VaultBackground._stop?.call();
    },
  );
}
