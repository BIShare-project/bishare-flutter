import 'dart:convert';
import 'dart:typed_data';

import 'package:bishare/core/rust/rust_facade.dart';
import 'package:bishare/features/vault/data/google_app_data.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_key_copy.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_signin.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// drive-plan.md task 3.6: the key copy in iCloud Keychain and in the
/// app-data folder of Google Drive. Google's REST API is replaced by a
/// recorder; the sealing is the real Rust code.
void main() {
  late bool rust;
  setUpAll(() async {
    rust = await initRustForTests();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  const vaultId = 'efgtkgwp3kofr2frtdwl7llgbe';
  final serverHalf = Uint8List.fromList(List.generate(32, (i) => i));

  group('VaultKeyCopy', () {
    test('save writes a sealed copy everywhere and reads it back', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final a = _MemHolder('icloud');
      final b = _MemHolder('google');
      final copy = VaultKeyCopy([a, b]);
      final vk = Rust.vaultGenerateKey();
      await copy.save(vaultId: vaultId, vaultKey: vk, serverHalf: serverHalf, interactive: true);
      expect(copy.stateOf('icloud'), KeyCopyState.saved);
      expect(copy.stateOf('google'), KeyCopyState.saved);
      expect(b.interactiveWrites, 1);
      // What leaves the device is the sealed copy, never the key itself.
      final stored = a.files[vaultId]!;
      expect(utf8.decode(stored.sublist(0, 4)), 'BSVK');
      expect(_contains(stored, vk), isFalse);
      expect(Rust.vaultOpenKeyCopy(serverHalf: serverHalf, vaultId: vaultId, keyCopy: stored), vk);
    });

    test('restore takes the first copy that matches the key check', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final vk = Rust.vaultGenerateKey();
      final sealed = Rust.vaultSealKeyCopy(serverHalf: serverHalf, vaultId: vaultId, vaultKey: vk);
      final icloud = _MemHolder('icloud'); // not synced yet
      final google = _MemHolder('google')..files[vaultId] = sealed;
      final copy = VaultKeyCopy([icloud, google]);
      final got = await copy.restore(vaultId: vaultId, serverHalf: serverHalf, keyCheck: Rust.vaultKeyCheck(vk));
      expect(got, vk);
      expect(copy.stateOf('icloud'), KeyCopyState.missing);
      expect(copy.stateOf('google'), KeyCopyState.saved);
    });

    test('a copy for another key, or one the server half cannot open, is refused', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final vk = Rust.vaultGenerateKey();
      final other = Rust.vaultSealKeyCopy(serverHalf: serverHalf, vaultId: vaultId, vaultKey: Rust.vaultGenerateKey());
      final garbage = Uint8List.fromList(List.filled(65, 7));
      final copy = VaultKeyCopy([_MemHolder('icloud')..files[vaultId] = other, _MemHolder('google')..files[vaultId] = garbage]);
      expect(await copy.restore(vaultId: vaultId, serverHalf: serverHalf, keyCheck: Rust.vaultKeyCheck(vk)), isNull);
      expect(copy.stateOf('icloud'), KeyCopyState.failed);
      expect(copy.stateOf('google'), KeyCopyState.failed);
    });

    test('a place that needs the person, or fails, never throws', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final copy = VaultKeyCopy([_MemHolder('google')..unreachable = true, _MemHolder('icloud')..broken = true]);
      await copy.save(vaultId: vaultId, vaultKey: Rust.vaultGenerateKey(), serverHalf: serverHalf);
      expect(copy.stateOf('google'), KeyCopyState.unreachable);
      expect(copy.stateOf('icloud'), KeyCopyState.failed);
    });

    test('repair writes the copy again only where it is missing or wrong', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final vk = Rust.vaultGenerateKey();
      final good = Rust.vaultSealKeyCopy(serverHalf: serverHalf, vaultId: vaultId, vaultKey: vk);
      final kept = _MemHolder('icloud')..files[vaultId] = good;
      final gone = _MemHolder('google');
      final copy = VaultKeyCopy([kept, gone]);
      await copy.repair(vaultId: vaultId, vaultKey: vk, serverHalf: serverHalf);
      expect(kept.writes, 0, reason: 'a copy that opens to the key is left alone');
      expect(gone.writes, 1);
      expect(copy.stateOf('google'), KeyCopyState.saved);
    });

    test('deleteAll clears every place and reports the ones it could not reach', () async {
      final a = _MemHolder('icloud')..files[vaultId] = Uint8List(1);
      final b = _MemHolder('google')
        ..files[vaultId] = Uint8List(1)
        ..unreachable = true;
      final left = await VaultKeyCopy([a, b]).deleteAll(vaultId);
      expect(a.files, isEmpty);
      expect(left, ['google']);
    });
  });

  test('the iCloud holder keeps the copy in the keychain under its vault id', () async {
    final h = ICloudKeyCopyHolder();
    final bytes = Uint8List.fromList([1, 2, 3, 250]);
    await h.write(vaultId, bytes);
    expect(await h.read(vaultId), bytes);
    expect(await h.read('another'), isNull);
    await h.delete(vaultId);
    expect(await h.read(vaultId), isNull);
  });

  group('GoogleAppData', () {
    test('creates the file in appDataFolder, then replaces it in place', () async {
      final g = _Google();
      final data = GoogleAppData(g.access, dio: g.dio);
      await data.write('vault-$vaultId.key', Uint8List.fromList([9, 8, 7]));
      final create = g.requests.last;
      expect(create.method, 'POST');
      expect(create.uri.path, '/upload/drive/v3/files');
      expect(create.uri.queryParameters['uploadType'], 'multipart');
      expect(create.headers['Authorization'], 'Bearer tok-1');
      final body = latin1.decode(create.body);
      expect(body, contains('"parents":["appDataFolder"]'));
      expect(body, contains('"name":"vault-$vaultId.key"'));
      expect(g.files['vault-$vaultId.key'], [9, 8, 7]);

      await data.write('vault-$vaultId.key', Uint8List.fromList([1]));
      expect(g.requests.last.method, 'PATCH');
      expect(g.requests.last.uri.path, '/upload/drive/v3/files/f1');
      expect(await data.read('vault-$vaultId.key'), [1]);
      // Every lookup stays inside the app-data folder.
      final lists = g.requests.where((r) => r.method == 'GET' && r.uri.path == '/drive/v3/files');
      expect(lists, isNotEmpty);
      expect(lists.every((r) => r.uri.queryParameters['spaces'] == 'appDataFolder'), isTrue);

      await data.delete('vault-$vaultId.key');
      expect(g.files, isEmpty);
      expect(await data.read('vault-$vaultId.key'), isNull);
    });

    test('a refused token is dropped and the call runs once more', () async {
      final g = _Google()..refuseFirst = true;
      final data = GoogleAppData(g.access, dio: g.dio);
      expect(await data.read('vault-$vaultId.key'), isNull);
      expect(g.access.invalidated, ['tok-1']);
      expect(g.requests.last.headers['Authorization'], 'Bearer tok-2');
    });

    test('no token without the person: GoogleAuthNeeded, nothing sent', () async {
      final g = _Google()..access.none = true;
      final data = GoogleAppData(g.access, dio: g.dio);
      await expectLater(data.read('vault-$vaultId.key'), throwsA(isA<GoogleAuthNeeded>()));
      expect(g.requests, isEmpty);
    });

    test('names outside the app\'s own pattern are refused before any request', () async {
      final g = _Google();
      final data = GoogleAppData(g.access, dio: g.dio);
      await expectLater(data.read("x' or name contains '"), throwsArgumentError);
      expect(g.requests, isEmpty);
    });
  });

  group('VaultAccount with the key copy', () {
    test('first device signed in with Google saves the copy, asking Google if needed', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final google = _MemHolder('google');
      final account = VaultAccount(keys: keys, api: _FakeApi(keys, keyCheck: null), keyCopy: VaultKeyCopy([google]));
      await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
      expect(account.status, VaultStatus.ready);
      expect(google.interactiveWrites, 1);
      expect(
        Rust.vaultOpenKeyCopy(serverHalf: (await keys.serverHalf())!, vaultId: _FakeApi.vaultId, keyCopy: google.files[_FakeApi.vaultId]!),
        await keys.vaultKey(),
      );
    });

    test('a second device signed in with Google gets the key with nothing typed', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final api = _FakeApi(keys, keyCheck: null);
      final vk = Rust.vaultGenerateKey();
      final google = _MemHolder('google')
        ..files[_FakeApi.vaultId] = Rust.vaultSealKeyCopy(serverHalf: api.serverHalf, vaultId: _FakeApi.vaultId, vaultKey: vk);
      final account = VaultAccount(
        keys: keys,
        api: _FakeApi(keys, keyCheck: Rust.vaultKeyCheck(vk)),
        keyCopy: VaultKeyCopy([google]),
      );
      await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
      expect(account.status, VaultStatus.ready);
      expect(await keys.vaultKey(), vk);
    });

    test('Apple sign-in never asks Google; a device still waiting finds the key at the next start', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final vk = Rust.vaultGenerateKey();
      final icloud = _MemHolder('icloud');
      final api = _FakeApi(keys, keyCheck: Rust.vaultKeyCheck(vk));
      final account = VaultAccount(keys: keys, api: api, keyCopy: VaultKeyCopy([icloud]));
      await account.completeSignIn(const ProviderToken(provider: 'apple', idToken: 't'));
      expect(account.status, VaultStatus.needsKey);
      expect(icloud.interactiveReads, 0);

      // iCloud Keychain syncs while the app is closed.
      icloud.files[_FakeApi.vaultId] = Rust.vaultSealKeyCopy(serverHalf: api.serverHalf, vaultId: _FakeApi.vaultId, vaultKey: vk);
      final later = VaultAccount(keys: keys, api: api, keyCopy: VaultKeyCopy([icloud]));
      await later.load();
      await pumpEventQueue();
      expect(later.status, VaultStatus.ready);
      expect(await keys.vaultKey(), vk);
    });

    test('a key that arrives by QR code or phrase is copied out too', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final keys = VaultKeyStore();
      final vk = Rust.vaultGenerateKey();
      final icloud = _MemHolder('icloud');
      final account = VaultAccount(keys: keys, api: _FakeApi(keys, keyCheck: Rust.vaultKeyCheck(vk)), keyCopy: VaultKeyCopy([icloud]));
      await account.completeSignIn(const ProviderToken(provider: 'apple', idToken: 't'));
      await account.acceptVaultKey(vk, Rust.vaultKeyCheck(vk));
      expect(icloud.files[_FakeApi.vaultId], isNotNull);
    });
  });
}

bool _contains(Uint8List hay, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

class _MemHolder implements KeyCopyHolder {
  _MemHolder(this.id);
  @override
  final String id;
  final files = <String, Uint8List>{};
  bool unreachable = false;
  bool broken = false;
  int writes = 0;
  int interactiveWrites = 0;
  int interactiveReads = 0;

  void _check() {
    if (unreachable) throw KeyCopyUnreachable(id);
    if (broken) throw StateError('broken');
  }

  @override
  Future<Uint8List?> read(String vaultId, {bool interactive = false}) async {
    if (interactive) interactiveReads++;
    _check();
    return files[vaultId];
  }

  @override
  Future<void> write(String vaultId, Uint8List copy, {bool interactive = false}) async {
    _check();
    writes++;
    if (interactive) interactiveWrites++;
    files[vaultId] = copy;
  }

  @override
  Future<void> delete(String vaultId, {bool interactive = false}) async {
    _check();
    files.remove(vaultId);
  }
}

class _Access implements GoogleDriveAccess {
  int _n = 0;
  bool none = false;
  final invalidated = <String>[];
  String? _current;

  @override
  Future<String?> accessToken({bool interactive = false}) async {
    if (none) return null;
    return _current ??= 'tok-${++_n}';
  }

  @override
  Future<void> invalidate(String token) async {
    invalidated.add(token);
    if (_current == token) _current = null;
  }
}

class _GReq {
  _GReq(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final Uint8List body;
}

/// Just enough of the Drive v3 API for one folder of small files.
class _Google implements HttpClientAdapter {
  final access = _Access();
  final requests = <_GReq>[];
  final files = <String, List<int>>{};
  final _ids = <String, String>{};
  bool refuseFirst = false;
  int _next = 0;

  Dio get dio => Dio()..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? stream, Future<void>? cancel) async {
    final bytes = <int>[];
    if (stream != null) {
      await for (final c in stream) {
        bytes.addAll(c);
      }
    }
    final req = _GReq(o.method, o.uri, o.headers, Uint8List.fromList(bytes));
    requests.add(req);
    if (refuseFirst) {
      refuseFirst = false;
      return ResponseBody.fromString('{"error":{"code":401}}', 401, headers: _json);
    }
    final path = o.uri.path;
    if (o.method == 'GET' && path == '/drive/v3/files') {
      final m = RegExp(r"name = '([^']+)'").firstMatch(o.uri.queryParameters['q'] ?? '');
      final id = _ids[m?.group(1)];
      return _reply({'files': [if (id != null) {'id': id}]});
    }
    if (o.method == 'GET' && path.startsWith('/drive/v3/files/')) {
      final name = _ids.entries.firstWhere((e) => e.value == path.split('/').last).key;
      return ResponseBody.fromBytes(files[name]!, 200);
    }
    if (o.method == 'POST' && path == '/upload/drive/v3/files') {
      final text = latin1.decode(bytes);
      final name = RegExp(r'"name":"([^"]+)"').firstMatch(text)!.group(1)!;
      final start = text.indexOf('application/octet-stream\r\n\r\n') + 'application/octet-stream\r\n\r\n'.length;
      final end = text.lastIndexOf('\r\n--bishare-vault-key-copy--');
      files[name] = bytes.sublist(start, end);
      _ids[name] = 'f${++_next}';
      return _reply({'id': _ids[name]});
    }
    if (o.method == 'PATCH' && path.startsWith('/upload/drive/v3/files/')) {
      final name = _ids.entries.firstWhere((e) => e.value == path.split('/').last).key;
      files[name] = bytes;
      return _reply({'id': _ids[name]});
    }
    if (o.method == 'DELETE') {
      final name = _ids.entries.firstWhere((e) => e.value == path.split('/').last).key;
      _ids.remove(name);
      files.remove(name);
      return ResponseBody.fromString('', 204);
    }
    return ResponseBody.fromString('{}', 404, headers: _json);
  }

  static final _json = {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  };

  ResponseBody _reply(Object body) => ResponseBody.fromString(jsonEncode(body), 200, headers: _json);

  @override
  void close({bool force = false}) {}
}

/// The server as VaultAccount sees it, without HTTP.
class _FakeApi extends VaultApi {
  _FakeApi(super.keys, {required this.keyCheck});

  static const vaultId = 'efgtkgwp3kofr2frtdwl7llgbe';
  final String? keyCheck;
  final serverHalf = Uint8List.fromList(List.generate(32, (i) => i));

  @override
  Future<VaultSigninResult> signin({required String provider, required String idToken, String? appleCode}) async =>
      VaultSigninResult(
        vaultId: vaultId,
        created: keyCheck == null,
        state: 'free',
        plan: 'free',
        quotaBytes: 5000000000,
        security: 'standard',
        keyCheck: keyCheck,
        deviceId: 'device',
        deviceStatus: 'active',
        serverHalf: serverHalf,
      );

  @override
  Future<void> registerKeyCheck(String vaultId, String keyCheck) async {}

  @override
  Future<Map<String, dynamic>> info(String vaultId) async => {'vaultId': vaultId, 'keyCheck': keyCheck};
}
