import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_downloader.dart';
import 'package:bishare/features/vault/data/vault_files.dart';
import 'package:bishare/features/vault/data/vault_key_copy.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_signin.dart';
import 'package:bishare/features/vault/data/vault_sync.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// drive-plan.md phase 4, end to end against a LOCAL Drive worker (never
/// production): two devices of one account, uploads small, compressed,
/// duplicate and multipart, an upload killed after its first part and
/// resumed, downloads byte for byte with their modification times, folder
/// changes seen by the other device, and the quota refused by the server.
///
/// Opt-in, like vault_flow.mjs:
///
///   VAULT_LOCAL_API=http://localhost:8799 \
///   VAULT_MINT=~/Documents/bishare-project/regression-tools/vault_mint_token.mjs \
///   flutter test test/vault_e2e_local_test.dart
///
/// The worker setup is in regression-tools/README.md ("BIShare Drive").
void main() {
  final api = Platform.environment['VAULT_LOCAL_API'];
  final mint = Platform.environment['VAULT_MINT'];
  if (api == null || mint == null) {
    test('Drive end to end skipped: VAULT_LOCAL_API / VAULT_MINT not set', () {});
    return;
  }
  if (!RegExp(r'^http://(localhost|127\.0\.0\.1):\d+$').hasMatch(api)) {
    throw StateError('VAULT_LOCAL_API must be a localhost URL');
  }

  late bool rust;
  late Directory tmp;
  setUpAll(() async {
    // Two installations in one process means two databases, on purpose.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    rust = await initRustForTests();
    tmp = await Directory.systemTemp.createTemp('vault_e2e');
  });
  tearDownAll(() => tmp.delete(recursive: true));

  final rng = Random(7);
  final subject = 'e2e-${DateTime.now().microsecondsSinceEpoch}';

  Future<File> file(String name, Uint8List bytes, DateTime mtime) async {
    final f = File('${tmp.path}/src/$name');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    await f.setLastModified(mtime);
    return f;
  }

  Uint8List random(int n) => Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));

  test('two devices, every way a file goes in and comes back', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final a = await _Device.signIn('a', api, mint, subject, tmp);
    expect(a.account.status, VaultStatus.ready);

    // ---- uploads -----------------------------------------------------------------
    final when = DateTime.utc(2024, 3, 9, 10, 30);
    final hello = await file('hello.txt', Uint8List.fromList('hello Drive\n'.codeUnits), when);
    final csv = await file('table.csv', Uint8List.fromList(List.generate(2 << 20, (i) => '0123456789,\n'.codeUnitAt(i % 12))), when);
    final bin = await file('random.bin', random(3 << 20), when);
    final big = await file('big.bin', random(120 << 20), when);
    final photos = await a.files.mkdir('Photos');
    await a.uploader.enqueue([hello, csv, bin]);
    await a.uploader.enqueue([big], parent: photos);
    await a.uploader.run();
    final putsBefore = a.puts;
    final copy = await file('copy.bin', await bin.readAsBytes(), when);
    await a.uploader.enqueue([copy]);
    await a.uploader.run();
    expect(a.puts, putsBefore, reason: 'the same content is linked, not sent again');
    expect(await a.failed(), isEmpty);
    await a.sync.pull();
    final top = await a.db.vaultDao.watchChildren(null).first;
    expect(top.map((o) => o.name), ['Photos', 'copy.bin', 'hello.txt', 'random.bin', 'table.csv']);
    final csvRow = top.firstWhere((o) => o.name == 'table.csv');
    expect(csvRow.blobSize!, lessThan(csvRow.size! ~/ 10), reason: 'stored compressed');
    final copyRow = top.firstWhere((o) => o.name == 'copy.bin');
    expect(copyRow.blobId, top.firstWhere((o) => o.name == 'random.bin').blobId, reason: 'one blob for both');

    // ---- the second device ------------------------------------------------------------
    final b = await _Device.signIn('b', api, mint, subject, tmp);
    expect(b.account.status, VaultStatus.needsKey);
    await b.account.acceptPhrase((await a.account.phrase())!);
    await b.sync.pull();
    final seen = await b.db.vaultDao.watchChildren(null).first;
    expect(seen.map((o) => o.name), top.map((o) => o.name));
    final inPhotos = await b.db.vaultDao.watchChildren(seen.first.id).first;
    expect(inPhotos.single.name, 'big.bin');

    for (final (row, src) in [
      (seen.firstWhere((o) => o.name == 'hello.txt'), hello),
      (seen.firstWhere((o) => o.name == 'table.csv'), csv),
      (seen.firstWhere((o) => o.name == 'copy.bin'), bin),
      (inPhotos.single, big),
    ]) {
      final out = await b.downloader.download(row.id, File('${tmp.path}/b-out/${row.name}'));
      expect(await out.readAsBytes(), await src.readAsBytes(), reason: row.name);
      expect((await out.lastModified()).toUtc(), when, reason: '${row.name} keeps its time');
    }

    // ---- folder changes, seen by the other device ----------------------------------------
    final helloId = seen.firstWhere((o) => o.name == 'hello.txt').id;
    final binId = seen.firstWhere((o) => o.name == 'random.bin').id;
    await b.files.rename(helloId, 'hi.txt');
    await b.files.move([binId], photos);
    await b.files.trash([photos]);
    await a.sync.pull();
    expect((await a.db.vaultDao.watchChildren(null).first).map((o) => o.name), ['copy.bin', 'hi.txt', 'table.csv']);
    expect((await a.db.vaultDao.watchTrash().first).map((o) => o.name).toSet(), {'Photos', 'big.bin', 'random.bin'});
    await a.files.restore([photos]);
    await b.sync.pull();
    expect((await b.db.vaultDao.watchChildren(photos).first).map((o) => o.name), ['big.bin', 'random.bin']);
    await b.files.deleteForGood([copyRow.id]);
    await a.sync.pull();
    expect(await a.db.vaultDao.object(copyRow.id), isNull);
    // The blob stays while random.bin still points at it.
    final still = await a.downloader.download(binId, File('${tmp.path}/a-out/random.bin'));
    expect(await still.readAsBytes(), await bin.readAsBytes());
    await expectLater(a.files.move([photos], photos), throwsA(isA<VaultApiException>()));

    // ---- an upload killed after its first part, then resumed ----------------------------------
    final big2 = await file('big2.bin', random(110 << 20), when);
    a.failPutsAfter = a.puts + 1;
    await a.uploader.enqueue([big2]);
    await a.uploader.run();
    final stuck = (await a.db.vaultDao.pendingTransfers()).single;
    expect(stuck.state, 'sending');
    expect(stuck.partsDone, contains('"n":1'));
    final resumed = a.restart();
    final putsAtRestart = resumed.puts;
    await resumed.uploader.run();
    expect(resumed.puts - putsAtRestart, 2, reason: 'parts 2 and 3 only');
    expect(await resumed.failed(), isEmpty);
    await resumed.sync.pull();
    final big2Row = (await resumed.db.vaultDao.watchChildren(null).first).firstWhere((o) => o.name == 'big2.bin');
    final out2 = await b.downloader.download(big2Row.id, File('${tmp.path}/b-out/big2.bin'));
    // b's index does not have it yet: it pulls first.
    expect(await out2.length(), 110 << 20);

    // ---- the server, not the app, holds the quota ---------------------------------------------
    final vaultId = (await a.keys.vaultId())!;
    await expectLater(
      a.api.reserve(vaultId, size: 6000000000),
      throwsA(isA<VaultApiException>().having((e) => e.code, 'code', 'STORAGE_LIMIT_EXCEEDED')),
    );

    // ---- delete the account -----------------------------------------------------------------
    await a.account.deleteAccount('google');
    expect(a.account.status, VaultStatus.signedOut);
  }, timeout: const Timeout(Duration(minutes: 10)));
}

/// One app installation: its own keychain, database and work folders.
class _Device {
  _Device._(this.name, this.apiBase, this.mint, this.subject, this.dir, this.keys, this.db);

  final String name;
  final String apiBase;
  final String mint;
  final String subject;
  final Directory dir;
  final VaultKeyStore keys;
  final AppDatabase db;
  late VaultApi api;
  late VaultAccount account;
  late VaultSync sync;
  late VaultUploader uploader;
  late VaultDownloader downloader;
  late VaultFiles files;
  int puts = 0;
  int? failPutsAfter;

  static Future<_Device> signIn(String name, String api, String mint, String subject, Directory tmp) async {
    final d = _Device._(name, api, mint, subject, tmp, VaultKeyStore(_Mem()), AppDatabase(NativeDatabase.memory()));
    d._wire();
    await d.account.completeSignIn(
      ProviderToken(provider: 'google', idToken: await d.token(await d.keys.signinNonce())),
    );
    return d;
  }

  /// The same installation after the app was killed: new objects, same
  /// keychain, database and files.
  _Device restart() {
    final again = _Device._(name, apiBase, mint, subject, dir, keys, db)..puts = puts;
    again._wire();
    return again;
  }

  void _wire() {
    api = VaultApi(keys, dio: Dio(BaseOptions(baseUrl: apiBase, responseType: ResponseType.json)));
    account = VaultAccount(keys: keys, api: api, signin: _Signin(this), keyCopy: VaultKeyCopy(const []));
    sync = VaultSync(api: api, keys: keys, dao: db.vaultDao);
    final http = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'PUT') {
              // Every PUT past the limit fails, as if the app had been killed:
              // the part's retries run out and the upload stops.
              if (failPutsAfter != null && puts >= failPutsAfter!) {
                return h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
              }
              puts++;
            }
            h.next(o);
          },
        ),
      );
    Future<Directory> work() async => Directory('${dir.path}/$name-work')..createSync(recursive: true);
    uploader = VaultUploader(api: api, keys: keys, dao: db.vaultDao, sync: sync, http: http, workDir: work);
    downloader = VaultDownloader(api: api, keys: keys, dao: db.vaultDao, sync: sync, workDir: work);
    files = VaultFiles(api: api, keys: keys, dao: db.vaultDao, sync: sync);
  }

  Future<String> token(String nonce) async {
    final r = await Process.run('node', [mint, 'google', subject, nonce]);
    if (r.exitCode != 0) throw StateError('mint failed: ${r.stderr}');
    return r.stdout as String;
  }

  Future<List<String>> failed() async => [
    for (final t in await db.vaultDao.watchTransfers().first)
      if (t.state == 'failed') '${t.name}: ${t.error}',
  ];
}

class _Signin extends VaultSignin {
  _Signin(this.device) : super(device.keys);
  final _Device device;

  @override
  Future<ProviderToken?> google(String nonce) async => ProviderToken(provider: 'google', idToken: await device.token(nonce));

  @override
  Future<void> forgetGoogle() async {}
}

class _Mem extends FlutterSecureStorage {
  _Mem();
  final _m = <String, String>{};

  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      _m[key];

  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }

  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, WebOptions? webOptions, AppleOptions? mOptions, WindowsOptions? wOptions}) async =>
      _m.remove(key);
}
