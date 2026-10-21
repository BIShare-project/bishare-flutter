import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_photo_backup.dart';
import 'package:bishare/features/vault/data/vault_photo_library.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/rust_test_lib.dart';
import 'helpers/vault_local.dart';

/// A camera roll of JPEG files in a folder, newest first.
class _DiskLibrary implements PhotoLibrary {
  _DiskLibrary(this.files);

  final List<File> files;

  late final List<PhotoAsset> _assets = [
    for (var i = 0; i < files.length; i++)
      PhotoAsset(
        id: 'p$i',
        video: false,
        taken: DateTime(2026, 10, 1).subtract(Duration(minutes: i)),
      ),
  ];

  @override
  bool get available => true;
  @override
  Future<PhotoAccess> access({bool ask = false}) async => PhotoAccess.full;
  @override
  Future<int> count() async => files.length;
  @override
  Future<List<PhotoAsset>> page(int page, int size) async =>
      _assets.skip(page * size).take(size).toList();
  @override
  Future<({File file, String name})?> original(PhotoAsset asset) async {
    final f = files[int.parse(asset.id.substring(1))];
    return (file: f, name: f.uri.pathSegments.last);
  }

  @override
  Future<Uint8List?> thumbnail(PhotoAsset asset, int size) async => null;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> chooseMore() async {}
}

/// drive-plan.md phase 5 gate, against a LOCAL Drive worker (never
/// production): a library of VAULT_PHOTOS photos (5,000 by default) is
/// backed up once and only once, across a restart of the app and a
/// reinstall; it waits on mobile data while "Wi-Fi only" is on; the count of
/// what is left is right.
///
///   VAULT_LOCAL_API=http://localhost:8799 \
///   VAULT_MINT=~/Documents/bishare-project/regression-tools/vault_mint_token.mjs \
///   VAULT_PHOTOS=5000 \
///   flutter test test/vault_photo_gate_local_test.dart
void main() {
  final api = Platform.environment['VAULT_LOCAL_API'];
  final mint = Platform.environment['VAULT_MINT'];
  final count = int.tryParse(Platform.environment['VAULT_PHOTOS'] ?? '');
  if (api == null || mint == null || count == null) {
    test(
      'photo gate skipped: VAULT_LOCAL_API / VAULT_MINT / VAULT_PHOTOS not set',
      () {},
    );
    return;
  }
  if (!RegExp(r'^http://(localhost|127\.0\.0\.1):\d+$').hasMatch(api)) {
    throw StateError('VAULT_LOCAL_API must be a localhost URL');
  }

  late Directory tmp;
  late _DiskLibrary library;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    expect(await initRustForTests(), isTrue);
    tmp = await Directory.systemTemp.createTemp('vault_photo_gate');
    final dir = await Directory('${tmp.path}/DCIM').create();
    // Small, distinct, real JPEGs: the uploader makes a thumbnail of each.
    final rnd = Random(5);
    final files = <File>[];
    for (var i = 0; i < count; i++) {
      final im = img.Image(width: 96, height: 72);
      for (final p in im) {
        p
          ..r = rnd.nextInt(256)
          ..g = rnd.nextInt(256)
          ..b = rnd.nextInt(256);
      }
      final f = File('${dir.path}/IMG_${i.toString().padLeft(5, '0')}.jpg');
      await f.writeAsBytes(img.encodeJpg(im, quality: 70));
      files.add(f);
    }
    library = _DiskLibrary(files);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  VaultPhotoBackup backupOf(
    VaultLocalDevice d,
    SharedPreferences prefs,
    bool Function() wifi,
  ) => VaultPhotoBackup(
    library: library,
    dao: d.db.vaultDao,
    uploader: d.uploader,
    files: d.files,
    keys: d.keys,
    prefs: prefs,
    folderName: () => 'Camera',
    onWifi: () async => wifi(),
    networkChanges: const Stream.empty(),
    catchUp: d.sync.pull,
  );

  /// One look at the library and the uploads it makes, as a background run
  /// does (the long budget: it ends when the work does).
  Future<void> run(VaultPhotoBackup b, VaultLocalDevice d) async {
    d.uploader.release();
    await b.runInBackground(const Duration(hours: 2));
  }

  Future<List<String>> cameraFiles(VaultLocalDevice d) async {
    final folder = await d.db.vaultDao.stateValue('photoBackupFolder');
    final dirs = (await d.db.vaultDao.liveChildren(
      null,
    )).where((o) => o.kind == 'dir' && o.name == 'Camera').toList();
    expect(dirs, hasLength(1), reason: 'one Camera folder');
    if (folder != null) expect(dirs.single.id, folder);
    return [
      for (final o in await d.db.vaultDao.liveChildren(dirs.single.id))
        if (o.kind == 'file') o.name,
    ];
  }

  test('the library goes up once and only once; mobile data waits; the count '
      'is right', () async {
    final subject = 'photo-gate-${DateTime.now().microsecondsSinceEpoch}';
    final a = await VaultLocalDevice.signIn('a', api, mint, subject, tmp);
    expect(a.account.status, VaultStatus.ready);
    SharedPreferences.setMockInitialValues({'vault.photoBackup': true});
    final prefs = await SharedPreferences.getInstance();

    // On mobile data with "Wi-Fi only": a batch is queued, nothing sent.
    var wifi = false;
    var backup = backupOf(a, prefs, () => wifi);
    await run(backup, a);
    expect(a.puts, 0, reason: 'nothing goes up on mobile data');
    expect(backup.left, count);
    final waiting = await a.db.vaultDao.pendingTransfers();
    expect(waiting, isNotEmpty);
    expect(waiting.every((t) => t.assetId != null), isTrue);

    // On Wi-Fi: everything, batch after batch.
    wifi = true;
    final watch = Stopwatch()..start();
    while ((await a.db.vaultDao.backedUpAssetIds()).length < count) {
      final before = (await a.db.vaultDao.backedUpAssetIds()).length;
      await run(backup, a);
      final after = (await a.db.vaultDao.backedUpAssetIds()).length;
      debugPrint('backed up $after of $count (${watch.elapsed.inSeconds} s)');
      if (after == before) {
        final failed = await a.failed();
        fail('no progress; failed: ${failed.take(5)}');
      }
    }
    debugPrint('all $count up in ${watch.elapsed.inSeconds} s');
    expect(await a.failed(), isEmpty);
    expect(backup.left, 0, reason: 'nothing left');
    await a.sync.pull();
    final names = await cameraFiles(a);
    expect(names, hasLength(count));
    expect(names.toSet(), hasLength(count), reason: 'no file twice');
    final sent = a.puts;

    // The app killed and opened again: same keychain and index.
    final again = a.restart();
    backup = backupOf(again, prefs, () => wifi);
    await run(backup, again);
    expect(again.puts, sent, reason: 'nothing sent again after a restart');
    expect(backup.left, 0);

    // A reinstall: a new installation of the same account, empty index,
    // the key from the phrase. The photos are found in the Drive by their
    // content, nothing is sent.
    final c = await VaultLocalDevice.signIn('c', api, mint, subject, tmp);
    await c.account.acceptPhrase((await a.account.phrase())!);
    expect(c.account.status, VaultStatus.ready);
    SharedPreferences.setMockInitialValues({'vault.photoBackup': true});
    final fresh = await SharedPreferences.getInstance();
    await c.sync.pull();
    backup = backupOf(c, fresh, () => true);
    final reinstall = Stopwatch()..start();
    while ((await c.db.vaultDao.backedUpAssetIds()).length < count) {
      final before = (await c.db.vaultDao.backedUpAssetIds()).length;
      await run(backup, c);
      if ((await c.db.vaultDao.backedUpAssetIds()).length == before) {
        fail('reinstall made no progress');
      }
    }
    debugPrint('reinstall matched $count in ${reinstall.elapsed.inSeconds} s');
    expect(c.puts, 0, reason: 'nothing sent again after a reinstall');
    expect(backup.left, 0);
    await c.sync.pull();
    expect(await cameraFiles(c), hasLength(count));
  }, timeout: const Timeout(Duration(hours: 2)));
}
