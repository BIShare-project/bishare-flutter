import 'dart:convert';
import 'dart:typed_data';

import 'package:bishare/core/rust/rust_facade.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_signin.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// drive-plan.md tasks 3.2 and 3.5: what the app sends to /api/v1/vault/* and
/// what it keeps. The HTTP layer is replaced by a recorder, so nothing leaves
/// the machine; the signatures are checked with the same Rust code the
/// server's vectors are pinned to.
void main() {
  late bool rust;
  setUpAll(() async {
    rust = await initRustForTests();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('a signed request verifies against the device key, path, time and exact body', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final keys = VaultKeyStore();
    final rec = _Recorder()..reply = {'success': true, 'data': {'keyCheck': 'x'}};
    final api = VaultApi(keys, dio: rec.dio)..now = () => DateTime.fromMillisecondsSinceEpoch(1728000000000);
    const vaultId = 'aaaqeayeaudaocajbifqydiob4';
    await api.registerKeyCheck(vaultId, 'AAAAAAAAAAAAAAAAAAAAAA');

    final req = rec.requests.single;
    expect(req.method, 'POST');
    expect(req.path, '/api/v1/vault/$vaultId/key');
    final auth = req.headers['Authorization'] as String;
    final fields = Map.fromEntries(
      auth.substring('BIShare-Vault '.length).split(',').map((f) => MapEntry(f.split('=')[0], f.substring(f.indexOf('=') + 1))),
    );
    expect(fields['vault'], vaultId);
    expect(fields['device'], await keys.deviceId());
    expect(fields['ts'], '1728000000');
    // The bytes on the wire are the bytes that were signed.
    expect(utf8.decode(req.body), '{"keyCheck":"AAAAAAAAAAAAAAAAAAAAAA"}');
    Rust.vaultVerifyRequest(
      publicKey: await keys.devicePublicKey(),
      method: 'POST',
      pathAndQuery: req.path,
      ts: 1728000000,
      body: req.body,
      signature: fields['sig']!,
    );
  });

  test('sign-in sends the device public key, unsigned; errors keep the server code', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final keys = VaultKeyStore();
    final rec = _Recorder()
      ..status = 401
      ..reply = {'success': false, 'error': {'code': 'VAULT_SIGNIN', 'message': 'nonce does not match this device'}};
    final api = VaultApi(keys, dio: rec.dio);
    await expectLater(
      api.signin(provider: 'google', idToken: 'tok'),
      throwsA(isA<VaultApiException>().having((e) => e.code, 'code', 'VAULT_SIGNIN').having((e) => e.status, 'status', 401)),
    );
    final req = rec.requests.single;
    expect(req.headers.containsKey('Authorization'), isFalse);
    final body = jsonDecode(utf8.decode(req.body)) as Map<String, dynamic>;
    expect(body['provider'], 'google');
    expect(_b64u(body['devicePublicKey'] as String), await keys.devicePublicKey());
    expect(body.containsKey('appleCode'), isFalse);
  });

  test('flag off: the plain 404 becomes VAULT_UNAVAILABLE', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final rec = _Recorder()
      ..status = 404
      ..reply = '404 page not found';
    final api = VaultApi(VaultKeyStore(), dio: rec.dio);
    await expectLater(api.signin(provider: 'google', idToken: 't'), throwsA(isA<VaultApiException>().having((e) => e.code, 'code', 'VAULT_UNAVAILABLE')));
  });

  test('the device key is made once and kept', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final a = await VaultKeyStore().deviceSeed();
    final b = await VaultKeyStore().deviceSeed();
    expect(a, hasLength(32));
    expect(b, a, reason: 'a second store reads the same seed from the keychain');
    expect(await VaultKeyStore().signinNonce(), Rust.vaultSigninNonce(Rust.vaultDevicePublicKey(a)));
  });

  group('VaultAccount', () {
    test('first device: makes the vault key and registers its key check', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final api = _FakeApi(keys, keyCheck: null);
      final account = VaultAccount(keys: keys, api: api);
      await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
      expect(account.status, VaultStatus.ready);
      final vk = await keys.vaultKey();
      expect(vk, hasLength(32));
      expect(api.registered, Rust.vaultKeyCheck(vk!));
      expect(await keys.serverHalf(), api.serverHalf);
      expect(await keys.vaultId(), _FakeApi.vaultId);
    });

    test('later device: needs the key, and accepts only the right one', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final vk = Rust.vaultGenerateKey();
      final account = VaultAccount(keys: keys, api: _FakeApi(keys, keyCheck: Rust.vaultKeyCheck(vk)));
      await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
      expect(account.status, VaultStatus.needsKey);
      expect(await keys.vaultKey(), isNull, reason: 'a later device never makes a second key');
      await expectLater(account.acceptVaultKey(Rust.vaultGenerateKey(), Rust.vaultKeyCheck(vk)), throwsA(isA<VaultApiException>()));
      await account.acceptVaultKey(vk, Rust.vaultKeyCheck(vk));
      expect(account.status, VaultStatus.ready);
      // After a restart the device is still ready.
      final again = VaultAccount(keys: VaultKeyStore(), api: _FakeApi(keys, keyCheck: Rust.vaultKeyCheck(vk)));
      await again.load();
      expect(again.status, VaultStatus.ready);
    });

    test('a race for the first key: the other device wins, this one waits for the key', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final account = VaultAccount(keys: keys, api: _FakeApi(keys, keyCheck: null, keyExists: true));
      await account.completeSignIn(const ProviderToken(provider: 'apple', idToken: 't'));
      expect(account.status, VaultStatus.needsKey);
      expect(await keys.vaultKey(), isNull);
      expect(await keys.vaultId(), _FakeApi.vaultId);
    });

    test('another account on the same device starts clean; sign-out keeps the device key', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final seed = await keys.deviceSeed();
      await keys.saveVault(vaultId: 'zzzzzzzzzzzzzzzzzzzzzzzzzz');
      await keys.saveVaultKey(Rust.vaultGenerateKey());
      final account = VaultAccount(keys: keys, api: _FakeApi(keys, keyCheck: 'AAAAAAAAAAAAAAAAAAAAAA'));
      await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
      expect(await keys.vaultKey(), isNull, reason: "the old account's key is gone");
      expect(account.status, VaultStatus.needsKey);
      await account.signOut();
      expect(account.status, VaultStatus.signedOut);
      expect(await keys.vaultId(), isNull);
      expect(await keys.deviceSeed(), seed);
    });

    test('Maximum security: a device that only signed in waits for approval', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final account = VaultAccount(keys: keys, api: _FakeApi(keys, keyCheck: 'AAAAAAAAAAAAAAAAAAAAAA', pending: true));
      await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
      expect(account.status, VaultStatus.pendingApproval);
      expect(await keys.serverHalf(), isNull);
    });
  });
}

class _Req {
  _Req(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Uint8List body;
}

/// A Dio whose adapter records each request and answers with [reply].
class _Recorder implements HttpClientAdapter {
  final requests = <_Req>[];
  Object reply = const {'success': true, 'data': null};
  int status = 200;

  Dio get dio => Dio(BaseOptions(baseUrl: 'http://vault.test'))..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    requests.add(_Req(options.method, options.uri.path + (options.uri.hasQuery ? '?${options.uri.query}' : ''), options.headers, Uint8List.fromList(bytes)));
    final text = reply is String ? reply as String : jsonEncode(reply);
    return ResponseBody.fromString(text, status, headers: {
      Headers.contentTypeHeader: [reply is String ? 'text/plain' : Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The server as VaultAccount sees it, without HTTP.
class _FakeApi extends VaultApi {
  _FakeApi(super.keys, {required this.keyCheck, this.keyExists = false, this.pending = false});

  static const vaultId = 'efgtkgwp3kofr2frtdwl7llgbe';
  final String? keyCheck;
  final bool keyExists;
  final bool pending;
  final serverHalf = Uint8List.fromList(List.generate(32, (i) => i));
  String? registered;

  @override
  Future<VaultSigninResult> signin({required String provider, required String idToken, String? appleCode}) async =>
      VaultSigninResult(
        vaultId: vaultId,
        created: keyCheck == null,
        state: 'free',
        plan: 'free',
        quotaBytes: 5000000000,
        security: pending ? 'maximum' : 'standard',
        keyCheck: keyCheck,
        deviceId: 'device',
        deviceStatus: pending ? 'pending' : 'active',
        serverHalf: pending ? null : serverHalf,
      );

  @override
  Future<void> registerKeyCheck(String vaultId, String keyCheck) async {
    if (keyExists) throw const VaultApiException('VAULT_KEY_EXISTS', 'This Drive already has a key', status: 409);
    registered = keyCheck;
  }
}

Uint8List _b64u(String s) => base64Url.decode(base64Url.normalize(s));
