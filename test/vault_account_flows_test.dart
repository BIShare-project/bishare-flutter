import 'dart:typed_data';

import 'package:bishare/core/rust/rust_facade.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_key_copy.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_signin.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// drive-plan.md tasks 3.7 to 3.9: the key by QR code and by phrase, linking
/// a second sign-in, and deleting the account. Two devices are two key stores
/// with their own keychains; the server is a fake that keeps pairing slots.
void main() {
  late bool rust;
  setUpAll(() async {
    rust = await initRustForTests();
  });

  const vaultId = 'efgtkgwp3kofr2frtdwl7llgbe';

  /// A device that has signed in and holds [vk] (or waits for it).
  Future<(VaultAccount, VaultKeyStore, _Server)> device(
    _Server server, {
    Uint8List? vk,
    List<KeyCopyHolder> holders = const [],
    List<String> log = const [],
  }) async {
    final keys = VaultKeyStore(_Mem());
    final account = VaultAccount(
      keys: keys,
      api: _Api(keys, server, log),
      signin: _Signin(keys, log),
      keyCopy: VaultKeyCopy(holders),
    );
    await account.completeSignIn(const ProviderToken(provider: 'google', idToken: 't'));
    if (vk != null && account.status != VaultStatus.ready) {
      await account.acceptVaultKey(vk, Rust.vaultKeyCheck(vk));
    }
    return (account, keys, server);
  }

  test('a new device gets the key from a QR code scanned by a device that has it', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final vk = Rust.vaultGenerateKey();
    final server = _Server(keyCheck: Rust.vaultKeyCheck(vk));
    final (old, _, _) = await device(server, vk: vk);
    final (fresh, freshKeys, _) = await device(server);
    expect(fresh.status, VaultStatus.needsKey);

    final pairing = await fresh.startPairing();
    expect(pairing.code, startsWith('BSVP1.${pairing.slot}.'));
    final waiting = fresh.awaitGrant(pairing, every: const Duration(milliseconds: 5));
    await old.grantTo(pairing.code);
    expect(await waiting, isTrue);
    expect(fresh.status, VaultStatus.ready);
    expect(await freshKeys.vaultKey(), vk);
    // What crossed the server was a sealed box, never the key.
    expect(server.boxes.single, isNot(contains(vk)));
  });

  test('a pairing code from another Drive is refused on the new device', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final vk = Rust.vaultGenerateKey();
    final server = _Server(keyCheck: Rust.vaultKeyCheck(vk));
    final (fresh, freshKeys, _) = await device(server);
    final pairing = await fresh.startPairing();
    server.slotVault = 'zzzzzzzzzzzzzzzzzzzzzzzzzz';
    final mine = Rust.vaultGrantKeyGenerate();
    server.fill(pairing.slot, Rust.vaultGrant(vaultKey: vk, vaultId: vaultId, mineSecret: mine.secret, newPub: pairing.publicKey), mine.public);
    await expectLater(
      fresh.awaitGrant(pairing, every: const Duration(milliseconds: 5)),
      throwsA(isA<VaultApiException>().having((e) => e.code, 'code', 'VAULT_KEY_MISMATCH')),
    );
    expect(await freshKeys.vaultKey(), isNull);
  });

  test('pairing codes: only the app\'s own shape is read', () {
    expect(() => VaultPairing.parse('bishare://r/abc'), throwsFormatException);
    expect(() => VaultPairing.parse('BSVP1.short.AAAA'), throwsFormatException);
    expect(() => VaultPairing.parse('BSVP1.${'A' * 22}.${'A' * 10}'), throwsFormatException);
    final ok = VaultPairing.parse(' BSVP1.${'A' * 22}.${'A' * 43} ');
    expect(ok.publicKey, hasLength(32));
  });

  test('the phrase brings the key; wrong words and another Drive\'s phrase do not', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final vk = Rust.vaultGenerateKey();
    final server = _Server(keyCheck: Rust.vaultKeyCheck(vk));
    final (old, _, _) = await device(server, vk: vk);
    final phrase = (await old.phrase())!;
    expect(phrase.split(' '), hasLength(24));

    final (fresh, freshKeys, _) = await device(server);
    await expectLater(
      fresh.acceptPhrase('these are not twenty four words'),
      throwsA(isA<VaultApiException>().having((e) => e.code, 'code', 'VAULT_PHRASE_INVALID')),
    );
    await expectLater(
      fresh.acceptPhrase(Rust.vaultPhraseFromKey(Rust.vaultGenerateKey())),
      throwsA(isA<VaultApiException>().having((e) => e.code, 'code', 'VAULT_KEY_MISMATCH')),
    );
    // Typed in capitals, with extra spaces and a line break.
    await fresh.acceptPhrase('  ${phrase.toUpperCase().replaceFirst(' ', '\n  ')}  ');
    expect(fresh.status, VaultStatus.ready);
    expect(await freshKeys.vaultKey(), vk);
  });

  test('linking Google uses a fresh sign-in and writes the key copy there', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final vk = Rust.vaultGenerateKey();
    final log = <String>[];
    final google = _Holder('google', log);
    final server = _Server(keyCheck: Rust.vaultKeyCheck(vk));
    final (account, keys, _) = await device(server, vk: vk, holders: [google], log: log);
    log.clear();
    expect(await account.link('google'), isTrue);
    expect(log, ['google sheet', 'link google fresh', 'write google interactive']);
    expect(account.linkedProviders, ['apple', 'google']);
    expect(google.files[vaultId], isNotNull);
    expect(await keys.vaultKey(), vk);
  });

  test('delete: fresh sign-in, key copy removed first, then the account, then this device forgets', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final vk = Rust.vaultGenerateKey();
    final log = <String>[];
    final google = _Holder('google', log);
    final icloud = _Holder('icloud', log);
    final server = _Server(keyCheck: Rust.vaultKeyCheck(vk));
    final (account, keys, _) = await device(server, vk: vk, holders: [icloud, google], log: log);
    expect(google.files, isNotEmpty);
    log.clear();
    final left = await account.deleteAccount('google');
    expect(left, isEmpty);
    expect(log, ['google sheet', 'delete icloud interactive', 'delete google interactive', 'delete account fresh', 'forget google']);
    expect(google.files, isEmpty);
    expect(icloud.files, isEmpty);
    expect(account.status, VaultStatus.signedOut);
    expect(await keys.vaultKey(), isNull);
    expect(await keys.vaultId(), isNull);
  });

  test('delete: closing the sign-in sheet changes nothing', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final vk = Rust.vaultGenerateKey();
    final log = <String>[];
    final server = _Server(keyCheck: Rust.vaultKeyCheck(vk));
    final (account, keys, _) = await device(server, vk: vk, log: log);
    _Signin.closeNext = true;
    expect(await account.deleteAccount('google'), isNull);
    expect(account.status, VaultStatus.ready);
    expect(await keys.vaultKey(), vk);
    expect(log, isNot(contains('delete account fresh')));
  });
}

/// A keychain of its own, so two devices in one test do not share one.
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

class _Signin extends VaultSignin {
  _Signin(super.keys, this.log);
  final List<String> log;
  static bool closeNext = false;

  @override
  Future<ProviderToken?> google(String nonce) async {
    if (closeNext) {
      closeNext = false;
      return null;
    }
    log.add('google sheet');
    return ProviderToken(provider: 'google', idToken: 'fresh:$nonce');
  }

  @override
  Future<void> forgetGoogle() async => log.add('forget google');
}

class _Holder implements KeyCopyHolder {
  _Holder(this.id, this.log);
  @override
  final String id;
  final List<String> log;
  final files = <String, Uint8List>{};

  String _i(bool interactive) => interactive ? ' interactive' : '';

  @override
  Future<Uint8List?> read(String vaultId, {bool interactive = false}) async => files[vaultId];

  @override
  Future<void> write(String vaultId, Uint8List copy, {bool interactive = false}) async {
    log.add('write $id${_i(interactive)}');
    files[vaultId] = copy;
  }

  @override
  Future<void> delete(String vaultId, {bool interactive = false}) async {
    log.add('delete $id${_i(interactive)}');
    files.remove(vaultId);
  }
}

/// The server's side of one Drive: its key check, linked sign-ins and the
/// pairing slots.
class _Server {
  _Server({required this.keyCheck});
  final String keyCheck;
  final serverHalf = Uint8List.fromList(List.generate(32, (i) => 255 - i));
  final identities = <String>['apple'];
  final _slots = <String, ({Uint8List box, Uint8List granterPub})?>{};
  final boxes = <Uint8List>[];
  String slotVault = 'efgtkgwp3kofr2frtdwl7llgbe';
  int _n = 0;

  String open() {
    final slot = 'slot${(++_n).toString().padLeft(18, '0')}';
    _slots[slot] = null;
    return slot;
  }

  void fill(String slot, Uint8List box, Uint8List granterPub) {
    if (!_slots.containsKey(slot)) {
      throw const VaultApiException('VAULT_PAIR_NOT_FOUND', 'gone', status: 404);
    }
    if (_slots[slot] != null) {
      throw const VaultApiException('VAULT_PAIR_TAKEN', 'taken', status: 409);
    }
    boxes.add(box);
    _slots[slot] = (box: box, granterPub: granterPub);
  }
}

class _Api extends VaultApi {
  _Api(super.keys, this.server, this.log);
  final _Server server;
  final List<String> log;

  @override
  Future<VaultSigninResult> signin({required String provider, required String idToken, String? appleCode}) async =>
      VaultSigninResult(
        vaultId: 'efgtkgwp3kofr2frtdwl7llgbe',
        created: false,
        state: 'free',
        plan: 'free',
        quotaBytes: 5000000000,
        security: 'standard',
        keyCheck: server.keyCheck,
        deviceId: 'device',
        deviceStatus: 'active',
        serverHalf: server.serverHalf,
      );

  @override
  Future<Map<String, dynamic>> info(String vaultId) async => {
    'vaultId': vaultId,
    'keyCheck': server.keyCheck,
    'identities': [
      for (final p in server.identities) {'provider': p, 'linkedAt': 0},
    ],
  };

  @override
  Future<void> linkIdentity(String vaultId, {required String provider, required String idToken}) async {
    log.add('link $provider ${idToken.startsWith('fresh:') ? 'fresh' : 'stale'}');
    server.identities.add(provider);
  }

  @override
  Future<void> deleteAccount(String vaultId, {required String provider, required String idToken, List<String> googleTokens = const []}) async {
    log.add('delete account ${idToken.startsWith('fresh:') ? 'fresh' : 'stale'}');
  }

  @override
  Future<String> openPairSlot() async => server.open();

  @override
  Future<void> fillPairSlot(String vaultId, String slot, {required Uint8List box, required Uint8List granterPub}) async =>
      server.fill(slot, box, granterPub);

  @override
  Future<({Uint8List box, Uint8List granterPub, String vaultId})?> takePairSlot(String slot) async {
    final s = server._slots[slot];
    if (s == null) return null;
    return (box: s.box, granterPub: s.granterPub, vaultId: server.slotVault);
  }
}
