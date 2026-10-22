// One installation of the app against a LOCAL Drive worker, for the opt-in
// end-to-end tests (vault_e2e_local_test.dart, vault_gate_local_test.dart):
// its own keychain, database and work folders, the real Drive classes wired
// as the app wires them, and sign-in tokens from the test issuer.
import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/rust/rust_facade.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_downloader.dart';
import 'package:bishare/features/vault/data/vault_downloads.dart';
import 'package:bishare/features/vault/data/vault_files.dart';
import 'package:bishare/features/vault/data/vault_key_copy.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_shares.dart';
import 'package:bishare/features/vault/data/vault_signin.dart';
import 'package:bishare/features/vault/data/vault_sync.dart';
import 'package:bishare/features/vault/data/vault_thumbs.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One app installation: its own keychain, database and work folders.
class VaultLocalDevice {
  VaultLocalDevice._(
    this.name,
    this.apiBase,
    this.mint,
    this.subject,
    this.dir,
    this.keys,
    this.db,
  );

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
  late VaultThumbs thumbs;
  late VaultShares shares;
  late VaultDownloads downloads;
  int puts = 0;
  int? failPutsAfter;

  static Future<VaultLocalDevice> signIn(
    String name,
    String api,
    String mint,
    String subject,
    Directory tmp,
  ) async {
    final d = VaultLocalDevice._(
      name,
      api,
      mint,
      subject,
      tmp,
      VaultKeyStore(MemSecureStorage()),
      AppDatabase(NativeDatabase.memory()),
    );
    d._wire();
    await d.account.completeSignIn(
      ProviderToken(
        provider: 'google',
        idToken: await d.token(await d.keys.signinNonce()),
      ),
    );
    return d;
  }

  /// The same installation after the app was killed: new objects, same
  /// keychain, database and files.
  /// A device that never signs in: Windows or Linux, approved by a phone.
  static VaultLocalDevice fresh(String name, String api, Directory tmp) =>
      VaultLocalDevice._(
        name,
        api,
        '',
        '',
        tmp,
        VaultKeyStore(MemSecureStorage()),
        AppDatabase(NativeDatabase.memory()),
      ).._wire();

  VaultLocalDevice restart() => at(apiBase);

  /// The same installation talking to [base] (a closed port: no network).
  VaultLocalDevice at(String base) {
    final again = VaultLocalDevice._(name, base, mint, subject, dir, keys, db)
      ..puts = puts;
    again._wire();
    return again;
  }

  /// A purchase from the worker's test store (local only): a bigger quota.
  Future<void> entitle(String productId) async {
    final vaultId = (await keys.vaultId())!;
    final path = '/api/v1/vault/$vaultId/entitlement';
    final body = utf8.encode(
      jsonEncode({
        'store': 'test',
        'productId': productId,
        'transactionId': 't-${DateTime.now().microsecondsSinceEpoch}',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 30))
            .millisecondsSinceEpoch,
      }),
    );
    final res = await Dio(BaseOptions(baseUrl: apiBase)).post<Object?>(
      path,
      data: body,
      options: Options(
        headers: {
          Headers.contentTypeHeader: Headers.jsonContentType,
          'Authorization': Rust.vaultAuthorization(
            seed: await keys.deviceSeed(),
            vaultId: vaultId,
            method: 'POST',
            pathAndQuery: path,
            ts: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            body: body,
          ),
        },
      ),
    );
    if (res.statusCode != 200) throw StateError('entitlement: ${res.data}');
  }

  void _wire() {
    api = VaultApi(
      keys,
      dio: Dio(BaseOptions(baseUrl: apiBase, responseType: ResponseType.json)),
    );
    account = VaultAccount(
      keys: keys,
      api: api,
      signin: _LocalSignin(this),
      keyCopy: VaultKeyCopy(const []),
      dao: db.vaultDao,
      deviceName: () => 'Device $name',
    );
    sync = VaultSync(api: api, keys: keys, dao: db.vaultDao);
    final http = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            if (o.method == 'PUT') {
              // Every PUT past the limit fails, as if the app had been killed:
              // the part's retries run out and the upload stops.
              if (failPutsAfter != null && puts >= failPutsAfter!) {
                return h.reject(
                  DioException(
                    requestOptions: o,
                    type: DioExceptionType.connectionError,
                  ),
                );
              }
              puts++;
            }
            h.next(o);
          },
        ),
      );
    Future<Directory> work() async =>
        Directory('${dir.path}/$name-work')..createSync(recursive: true);
    Future<Directory> thumbDir() async =>
        Directory('${dir.path}/$name-thumbs')..createSync(recursive: true);
    thumbs = VaultThumbs(
      api: api,
      keys: keys,
      dao: db.vaultDao,
      cacheDir: thumbDir,
    );
    uploader = VaultUploader(
      api: api,
      keys: keys,
      dao: db.vaultDao,
      sync: sync,
      http: http,
      workDir: work,
      thumbs: thumbs,
    );
    downloader = VaultDownloader(
      api: api,
      keys: keys,
      dao: db.vaultDao,
      sync: sync,
      workDir: work,
    );
    files = VaultFiles(api: api, keys: keys, dao: db.vaultDao, sync: sync);
    downloads = VaultDownloads(downloader: downloader, dao: db.vaultDao);
    shares = VaultShares(
      api: api,
      keys: keys,
      dao: db.vaultDao,
      downloads: downloads,
      cloud: () =>
          throw StateError('compressed files are not shared in this test'),
      senderAlias: () => name,
    );
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

class _LocalSignin extends VaultSignin {
  _LocalSignin(this.device) : super(device.keys);
  final VaultLocalDevice device;

  @override
  Future<ProviderToken?> google(String nonce) async =>
      ProviderToken(provider: 'google', idToken: await device.token(nonce));

  @override
  Future<void> forgetGoogle() async {}
}

class MemSecureStorage extends FlutterSecureStorage {
  MemSecureStorage();
  final _m = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _m[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _m.remove(key);
    } else {
      _m[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _m.remove(key);
}
