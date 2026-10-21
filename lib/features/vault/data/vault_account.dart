import 'package:flutter/foundation.dart';

import '../../../core/rust/rust_facade.dart';
import 'vault_api.dart';
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

/// Sign-in and the vault key on this device (drive-plan.md tasks 3.2 and
/// 3.5). The first device of an account makes the vault key and registers
/// its key check; any later device needs the key from somewhere else and
/// never makes a second one.
class VaultAccount extends ChangeNotifier {
  VaultAccount({
    required VaultKeyStore keys,
    required VaultApi api,
    VaultSignin? signin,
  }) : _keys = keys,
       _api = api,
       _signin = signin ?? VaultSignin();

  final VaultKeyStore _keys;
  final VaultApi _api;
  final VaultSignin _signin;

  VaultStatus _status = VaultStatus.signedOut;
  String? _vaultId;
  VaultSigninResult? _last;

  VaultStatus get status => _status;
  String? get vaultId => _vaultId;

  /// The answer of the latest sign-in on this run (plan, quota, state).
  VaultSigninResult? get lastSignin => _last;

  /// Read what this device already has; no network.
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
  }

  /// Forget Drive on this device. The account and its files stay.
  Future<void> signOut() async {
    await _keys.forgetVault();
    await _signin.forgetGoogle();
    _vaultId = null;
    _last = null;
    _status = VaultStatus.signedOut;
    notifyListeners();
  }
}
