import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_background.dart';
import 'package:bishare/features/vault/data/vault_files.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_photo_backup.dart';
import 'package:bishare/features/vault/data/vault_photo_library.dart';
import 'package:bishare/features/vault/data/vault_sync.dart';
import 'package:bishare/features/vault/data/vault_thumbs.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends Mock implements VaultApi {}

class _Keys extends Mock implements VaultKeyStore {}

class _Sync extends Mock implements VaultSync {}

class _Thumbs extends Mock implements VaultThumbs {}

class _Files extends Mock implements VaultFiles {}

class _Uploader extends Mock implements VaultUploader {}

class _Library extends Mock implements PhotoLibrary {}

/// Photo backup while the app is closed (drive-plan.md task 5.4): the run
/// leaves the work to an app that answers, stops when the app takes over,
/// and stops sending when its time is up; the uploader can be held.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() {
    IsolateNameServer.removePortNameMapping(VaultBackground.appPort);
    IsolateNameServer.removePortNameMapping(VaultBackground.runPort);
  });

  test('a run that finds the app answering hands the work to it', () async {
    final app = ReceivePort();
    IsolateNameServer.registerPortWithName(
      app.sendPort,
      VaultBackground.appPort,
    );
    final asked = <String>[];
    app.listen((m) {
      final [what as String, reply as SendPort] = m as List;
      asked.add(what);
      reply.send(what == 'ping' ? 'pong' : 'ok');
    });
    // No Rust, no keychain, no database: it never gets that far.
    expect(await VaultBackground.run(), isTrue);
    expect(asked, ['ping', 'backup']);
    app.close();
  });

  test('the app taking over waits for the run to stop', () async {
    final run = ReceivePort();
    IsolateNameServer.registerPortWithName(
      run.sendPort,
      VaultBackground.runPort,
    );
    var stopped = false;
    run.listen((m) async {
      final [what as String, reply as SendPort] = m as List;
      expect(what, 'stop');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      stopped = true;
      reply.send('stopped');
    });
    await VaultBackground.takeOver();
    expect(stopped, isTrue);
    run.close();

    // A run that died without saying so is forgotten.
    final dead = ReceivePort()..close();
    IsolateNameServer.registerPortWithName(
      dead.sendPort,
      VaultBackground.runPort,
    );
    await VaultBackground.takeOver(wait: const Duration(milliseconds: 100));
    expect(IsolateNameServer.lookupPortByName(VaultBackground.runPort), isNull);

    // Nothing running: at once.
    await VaultBackground.takeOver();
  });

  test('a held uploader starts nothing until released', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final uploader = VaultUploader(
      api: _Api(),
      keys: _Keys(),
      dao: db.vaultDao,
      sync: _Sync(),
      thumbs: _Thumbs(),
    );
    var before = 0;
    uploader.beforeRun = () async => before++;
    await uploader.hold();
    await uploader.run();
    expect(before, 0, reason: 'held: the queue was not even looked at');
    uploader.release();
    await uploader.run();
    expect(before, 1);
    await db.close();
  });

  test('a background run stops sending when its time is up', () async {
    SharedPreferences.setMockInitialValues({'vault.photoBackup': true});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final keys = _Keys();
    when(() => keys.vaultKey()).thenAnswer((_) async => null);
    final library = _Library();
    when(() => library.available).thenReturn(true);
    when(
      () => library.access(ask: any(named: 'ask')),
    ).thenAnswer((_) async => PhotoAccess.full);
    final uploader = _Uploader();
    // The queue never finishes by itself: only holding it ends the send.
    final sending = Completer<void>();
    when(uploader.run).thenAnswer((_) => sending.future);
    when(uploader.hold).thenAnswer((_) async {
      if (!sending.isCompleted) sending.complete();
    });
    final backup = VaultPhotoBackup(
      library: library,
      dao: db.vaultDao,
      uploader: uploader,
      files: _Files(),
      keys: keys,
      prefs: prefs,
      folderName: () => 'Camera',
      onWifi: () async => true,
      networkChanges: const Stream.empty(),
    );
    final watch = Stopwatch()..start();
    await backup.runInBackground(const Duration(milliseconds: 200));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    verify(uploader.hold).called(greaterThanOrEqualTo(1));
    expect(backup.scanning, isFalse);
    await db.close();
  });
}
