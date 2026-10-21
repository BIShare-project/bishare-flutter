import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/rust/rust_facade.dart';
import 'google_app_data.dart';
import 'vault_api.dart';
import 'vault_key_copy.dart';
import 'vault_keys.dart';
import 'vault_signin.dart';

/// Where this device stands with Drive.
enum VaultStatus {
  /// No Drive account on this device.
  signedOut,

  /// Signed in, and this device holds the vault key.
  ready,

  /// Signed in, but the vault key is not here yet: it comes from the key copy
  /// (task 3.6), a QR code from another device (3.8) or the phrase (3.7).
  needsKey,

  /// Maximum security: another device must approve this one first.
  pendingApproval,
}

/// Sign-in and the vault key on this device (drive-plan.md tasks 3.2, 3.5
/// and 3.6). The first device of an account makes the vault key and
/// registers its key check; any later device gets the key from the key copy,
/// a QR code or the phrase, and never makes a second one.
class VaultAccount extends ChangeNotifier {
  VaultAccount({
    required VaultKeyStore keys,
    required VaultApi api,
    VaultSignin? signin,
    VaultKeyCopy? keyCopy,
  }) : _keys = keys,
       _api = api {
    _signin = signin ?? VaultSignin(keys);
    this.keyCopy =
        keyCopy ??
        VaultKeyCopy([
          if (ICloudKeyCopyHolder.available) ICloudKeyCopyHolder(),
          GoogleKeyCopyHolder(GoogleAppData(_signin.googleDrive)),
        ]);
  }

  final VaultKeyStore _keys;
  final VaultApi _api;
  late final VaultSignin _signin;

  /// Where the key copy is, for "Ways back in" (task 3.7).
  late final VaultKeyCopy keyCopy;

  /// The start check of the key copy runs once per run of the app.
  bool _checked = false;

  VaultStatus _status = VaultStatus.signedOut;
  String? _vaultId;
  VaultSigninResult? _last;

  VaultStatus get status => _status;
  String? get vaultId => _vaultId;

  /// The answer of the latest sign-in on this run (plan, quota, state).
  VaultSigninResult? get lastSignin => _last;

  /// Read what this device already has, then, once per run and in the
  /// background, check the key copy: write it again where it went missing,
  /// or, on a device still waiting for the key, look for it (iCloud Keychain
  /// may have synced since).
  Future<void> load() async {
    _vaultId = await _keys.vaultId();
    if (_vaultId == null) {
      _status = VaultStatus.signedOut;
    } else {
      _status = await _keys.vaultKey() != null
          ? VaultStatus.ready
          : VaultStatus.needsKey;
    }
    notifyListeners();
    if (!_checked && _vaultId != null) {
      _checked = true;
      unawaited(_checkKeyCopy());
    }
  }

  Future<void> _checkKeyCopy() async {
    final vaultId = _vaultId;
    final serverHalf = await _keys.serverHalf();
    if (vaultId == null || serverHalf == null) return;
    try {
      if (_status == VaultStatus.ready) {
        await keyCopy.repair(
          vaultId: vaultId,
          vaultKey: (await _keys.vaultKey())!,
          serverHalf: serverHalf,
        );
      } else if (_status == VaultStatus.needsKey) {
        final keyCheck = (await _api.info(vaultId))['keyCheck'] as String?;
        if (keyCheck != null) {
          await _restore(vaultId, serverHalf, keyCheck, interactive: false);
        }
      }
    } on Object catch (e) {
      debugPrint('[vault] key copy check at start: $e');
    }
  }

  /// Look for the key in the key copy; on success the device is ready and the
  /// copy is written where it was missing.
  Future<void> _restore(
    String vaultId,
    Uint8List serverHalf,
    String keyCheck, {
    required bool interactive,
  }) async {
    final vk = await keyCopy.restore(
      vaultId: vaultId,
      serverHalf: serverHalf,
      keyCheck: keyCheck,
      interactive: interactive,
    );
    if (vk == null || _vaultId != vaultId) return;
    await _keys.saveVaultKey(vk);
    _status = VaultStatus.ready;
    notifyListeners();
    await keyCopy.repair(
      vaultId: vaultId,
      vaultKey: vk,
      serverHalf: serverHalf,
    );
  }

  /// Run the provider's sheet, then enrol this device. Returns false when the
  /// person closed the sheet. Throws [VaultSigninException] or
  /// [VaultApiException] on failure.
  Future<bool> signIn(String provider) async {
    final nonce = await _keys.signinNonce();
    final token = switch (provider) {
      'google' => await _signin.google(nonce),
      'apple' => await _signin.apple(nonce),
      _ => throw ArgumentError.value(provider, 'provider'),
    };
    if (token == null) return false;
    await completeSignIn(token);
    return true;
  }

  /// The part after the provider's sheet, separate so tests and the desktop
  /// flows (task 3.4) can hand in a token they got another way.
  Future<void> completeSignIn(ProviderToken token) async {
    final r = await _api.signin(
      provider: token.provider,
      idToken: token.idToken,
      appleCode: token.appleCode,
    );
    _last = r;
    // Another account was on this device before: its key must not be reused.
    final previous = await _keys.vaultId();
    if (previous != null && previous != r.vaultId) await _keys.forgetVault();
    await _keys.saveVault(vaultId: r.vaultId, serverHalf: r.serverHalf);
    _vaultId = r.vaultId;

    if (r.deviceStatus == 'pending') {
      _status = VaultStatus.pendingApproval;
    } else if (r.keyCheck == null) {
      await _makeVaultKey(r.vaultId);
    } else {
      final local = await _keys.vaultKey();
      _status = local != null && Rust.vaultKeyCheck(local) == r.keyCheck
          ? VaultStatus.ready
          : VaultStatus.needsKey;
    }
    notifyListeners();
    _checked = true;

    // The key copy, right after the tap, so Google may ask for its consent.
    final serverHalf = r.serverHalf;
    if (serverHalf == null) return;
    final interactive = token.provider == 'google';
    if (_status == VaultStatus.ready) {
      await keyCopy.save(
        vaultId: r.vaultId,
        vaultKey: (await _keys.vaultKey())!,
        serverHalf: serverHalf,
        interactive: interactive,
      );
    } else if (_status == VaultStatus.needsKey && r.keyCheck != null) {
      await _restore(
        r.vaultId,
        serverHalf,
        r.keyCheck!,
        interactive: interactive,
      );
    }
  }

  /// First device of the account: make VK, keep it, register its key check.
  Future<void> _makeVaultKey(String vaultId) async {
    final vk = await _keys.vaultKey() ?? Rust.vaultGenerateKey();
    await _keys.saveVaultKey(vk);
    try {
      await _api.registerKeyCheck(vaultId, Rust.vaultKeyCheck(vk));
      _status = VaultStatus.ready;
    } on VaultApiException catch (e) {
      if (e.code != 'VAULT_KEY_EXISTS') rethrow;
      // Another device of the same account registered first: its key wins,
      // and this device's own attempt is thrown away.
      await _keys.forgetVault();
      await _keys.saveVault(vaultId: vaultId, serverHalf: _last?.serverHalf);
      _status = VaultStatus.needsKey;
    }
  }

  /// Accept a vault key that arrived by key copy, QR code or phrase, after
  /// checking it against the account's key check.
  Future<void> acceptVaultKey(Uint8List key, String keyCheck) async {
    if (Rust.vaultKeyCheck(key) != keyCheck) {
      throw const VaultApiException(
        'VAULT_KEY_MISMATCH',
        'This key belongs to another Drive',
      );
    }
    await _keys.saveVaultKey(key);
    _status = VaultStatus.ready;
    notifyListeners();
    final vaultId = _vaultId;
    final serverHalf = await _keys.serverHalf();
    if (vaultId != null && serverHalf != null) {
      await keyCopy.save(
        vaultId: vaultId,
        vaultKey: key,
        serverHalf: serverHalf,
      );
    }
  }

  /// Forget Drive on this device. The account and its files stay.
  Future<void> signOut() async {
    await _keys.forgetVault();
    await _signin.forgetGoogle();
    keyCopy.reset();
    _vaultId = null;
    _last = null;
    _status = VaultStatus.signedOut;
    notifyListeners();
  }
}
