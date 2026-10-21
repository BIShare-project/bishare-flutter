import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/rust/rust_facade.dart';

/// Where this device keeps its Drive secrets (drive-plan.md task 3.5).
///
/// - the device key seed (Ed25519): made here, never leaves the device, signs
///   every request; the device id is derived from its public key;
/// - the vault key `VK` once the device has it, and the vault id;
/// - the server half of the key copy, which the server hands to a device at
///   sign-in and which is only useful together with the key copy.
///
/// Everything is in the platform keychain / keystore with this-device-only
/// accessibility: nothing here travels in a backup or to another device. The
/// copy that does travel is the key copy (task 3.6), sealed with the server
/// half. Unlike DeviceIdentity, there is no fallback to plain preferences: a
/// build whose keychain is unavailable (an ad-hoc-signed Mac build) cannot use
/// Drive, rather than keep the vault key in plain text.
class VaultKeyStore {
  VaultKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
            mOptions: MacOsOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static const _kSeed = 'vault.deviceSeed';
  static const _kVaultId = 'vault.id';
  static const _kVaultKey = 'vault.key';
  static const _kServerHalf = 'vault.serverHalf';
  static const _kGoogleHere = 'vault.googleHere';
  static const _kGoogleRefresh = 'vault.googleRefresh';

  Uint8List? _seed;

  /// The device key seed, made on first use and then kept for the life of the
  /// installation (also across account deletion, so the device id is stable).
  Future<Uint8List> deviceSeed() async {
    if (_seed != null) return _seed!;
    final stored = await _readBytes(_kSeed);
    if (stored != null && stored.length == 32) return _seed = stored;
    final made = Rust.vaultDeviceKeyGenerate();
    await _writeBytes(_kSeed, made);
    return _seed = made;
  }

  Future<Uint8List> devicePublicKey() async =>
      Rust.vaultDevicePublicKey(await deviceSeed());

  Future<String> deviceId() async =>
      Rust.vaultDeviceId(await devicePublicKey());

  /// The nonce every ID token for this device must carry (VAULT-SPEC "Sign-in nonce").
  Future<String> signinNonce() async =>
      Rust.vaultSigninNonce(await devicePublicKey());

  Future<String?> vaultId() => _storage.read(key: _kVaultId);

  Future<Uint8List?> vaultKey() => _readBytes(_kVaultKey);

  Future<Uint8List?> serverHalf() => _readBytes(_kServerHalf);

  Future<void> saveVault({
    required String vaultId,
    Uint8List? serverHalf,
  }) async {
    await _storage.write(key: _kVaultId, value: vaultId);
    if (serverHalf != null) await _writeBytes(_kServerHalf, serverHalf);
  }

  Future<void> saveVaultKey(Uint8List key) async {
    if (key.length != 32) throw ArgumentError('vault key must be 32 bytes');
    await _writeBytes(_kVaultKey, key);
  }

  /// Whether this device has signed in with Google for Drive, so it may ask
  /// Google for a Drive token at start without showing anything first.
  Future<bool> googleHere() async =>
      await _storage.read(key: _kGoogleHere) == '1';

  Future<void> setGoogleHere(bool here) => here
      ? _storage.write(key: _kGoogleHere, value: '1')
      : _storage.delete(key: _kGoogleHere);

  /// Windows and Linux only: the refresh token of the loopback flow
  /// (VaultGoogleDesktop). It never leaves this device.
  Future<String?> googleRefreshToken() => _storage.read(key: _kGoogleRefresh);

  Future<void> saveGoogleRefreshToken(String? token) => token == null
      ? _storage.delete(key: _kGoogleRefresh)
      : _storage.write(key: _kGoogleRefresh, value: token);

  /// Forget the vault on this device (sign-out, account deleted). The device
  /// key stays, and so does the Google state: it belongs to the provider
  /// sign-in, which VaultSignin.forgetGoogle clears.
  Future<void> forgetVault() async {
    await _storage.delete(key: _kVaultId);
    await _storage.delete(key: _kVaultKey);
    await _storage.delete(key: _kServerHalf);
  }

  Future<Uint8List?> _readBytes(String key) async {
    final v = await _storage.read(key: key);
    if (v == null || v.isEmpty) return null;
    try {
      return base64Url.decode(base64Url.normalize(v));
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeBytes(String key, List<int> bytes) => _storage.write(
    key: key,
    value: base64Url.encode(bytes).replaceAll('=', ''),
  );
}
