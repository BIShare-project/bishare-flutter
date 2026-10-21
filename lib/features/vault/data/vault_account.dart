import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/vault_tables.dart';
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
    VaultDao? dao,
    Future<void> Function()? onForget,
    String Function()? deviceName,
  }) : _keys = keys,
       _api = api,
       _dao = dao,
       _onForget = onForget,
       _deviceName = deviceName {
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

  /// The local index and queue; cleared on sign-out and when another account
  /// signs in on this device.
  final VaultDao? _dao;

  /// Caches outside the database (thumbnails, opened files) to drop with it.
  final Future<void> Function()? _onForget;

  /// The name this device goes by in the device list until renamed (the
  /// app's own device name, e.g. "Cakra's MacBook").
  final String Function()? _deviceName;

  /// Set when the server says this device was removed or the account is
  /// gone; the Drive screens say so once, then forget it.
  String? removedNotice;

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
    // Another account was on this device before: its key must not be reused,
    // and its index and queue go too.
    final previous = await _keys.vaultId();
    if (previous != null && previous != r.vaultId) {
      await _keys.forgetVault();
      await _dao?.clearAll();
      await _onForget?.call();
    }
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

  // ---- the account as the server sees it (task 3.7) ---------------------------

  Map<String, dynamic>? _info;

  /// The sign-ins linked to this Drive ("apple", "google"), once [refreshInfo]
  /// has run.
  List<String> get linkedProviders => [
    for (final i in (_info?['identities'] as List?) ?? const [])
      if (i is Map && i['provider'] is String) i['provider'] as String,
  ];

  /// Stored bytes (what the quota counts), as of the last [refreshInfo].
  int? get usedBytes => (_info?['usedBytes'] as num?)?.toInt();

  int? get quotaBytes =>
      (_info?['quotaBytes'] as num?)?.toInt() ?? _last?.quotaBytes;

  Future<void> refreshInfo() async {
    final id = _vaultId;
    if (id == null) return;
    try {
      _info = await _api.info(id);
    } on VaultApiException catch (e) {
      // Removed from another device, or the account was deleted there: this
      // device cannot come back without signing in again.
      final gone =
          e.code == 'VAULT_NOT_FOUND' ||
          (e.code == 'VAULT_AUTH' && e.message.contains('removed'));
      if (!gone) rethrow;
      removedNotice = e.code;
      await signOut();
      return;
    }
    notifyListeners();
    await _nameThisDevice();
  }

  // ---- devices (task 4.9) --------------------------------------------------------

  /// The devices of this Drive (removed ones left out), names opened.
  Future<List<VaultDeviceView>> devices() async {
    final vaultId = _vaultId;
    final vk = await _keys.vaultKey();
    final me = await _keys.deviceId();
    final out = <VaultDeviceView>[];
    for (final raw in (_info?['devices'] as List?) ?? const []) {
      final d = Map<String, dynamic>.from(raw as Map);
      if (d['status'] == 'revoked') continue;
      String? name;
      final enc = d['encName'] as String?;
      if (enc != null && vk != null && vaultId != null) {
        try {
          name = Rust.vaultOpenDeviceName(
            metaKey: Rust.vaultMetaKey(vk),
            vaultId: vaultId,
            deviceId: d['id'] as String,
            encName: enc,
          );
        } on Object {
          name = null;
        }
      }
      out.add(
        VaultDeviceView(
          id: d['id'] as String,
          name: name,
          thisDevice: d['id'] == me,
          pending: d['status'] == 'pending',
          addedAt: (d['addedAt'] as num?)?.toInt() ?? 0,
          lastSeenAt: (d['lastSeenAt'] as num?)?.toInt(),
        ),
      );
    }
    out.sort((a, b) {
      if (a.thisDevice != b.thisDevice) return a.thisDevice ? -1 : 1;
      return (b.lastSeenAt ?? 0).compareTo(a.lastSeenAt ?? 0);
    });
    return out;
  }

  /// Give a device of this Drive a name (sealed: the server cannot read it).
  Future<void> renameDevice(String deviceId, String name) async {
    final vaultId = _requireVault();
    final vk = await _keys.vaultKey();
    if (vk == null) {
      throw const VaultApiException('VAULT_NO_KEY', 'No key on this device');
    }
    final trimmed = name.trim();
    final enc = Rust.vaultSealDeviceName(
      metaKey: Rust.vaultMetaKey(vk),
      vaultId: vaultId,
      deviceId: deviceId,
      name: trimmed.length > 100 ? trimmed.substring(0, 100) : trimmed,
    );
    final r = await _api.ops(vaultId, [
      {
        'opId': Rust.vaultGenerateObjectId(),
        'type': 'device_name',
        'deviceId': deviceId,
        'encName': enc,
      },
    ]);
    final res = r.results.single;
    if (res['ok'] != true) {
      throw VaultApiException(
        res['code'] as String? ?? 'UNKNOWN',
        res['message'] as String? ?? '',
      );
    }
    _info = await _api.info(vaultId);
    notifyListeners();
  }

  /// Remove another device: it can no longer read or change anything, and
  /// cannot come back without signing in again. Needs a fresh sign-in.
  /// False when the person closed the sheet.
  Future<bool> removeDevice(String deviceId, String provider) async {
    final vaultId = _requireVault();
    final token = await _freshToken(provider);
    if (token == null) return false;
    await _api.removeDevice(
      vaultId,
      deviceId,
      provider: token.provider,
      idToken: token.idToken,
    );
    _info = await _api.info(vaultId);
    notifyListeners();
    return true;
  }

  bool _naming = false;

  /// The first time this device has the key, it takes the app's device name.
  Future<void> _nameThisDevice() async {
    final provide = _deviceName;
    if (provide == null || _naming || status != VaultStatus.ready) return;
    final me = await _keys.deviceId();
    final mine = ((_info?['devices'] as List?) ?? const [])
        .map((d) => Map<String, dynamic>.from(d as Map))
        .where((d) => d['id'] == me)
        .firstOrNull;
    if (mine == null || mine['encName'] != null) return;
    final name = provide().trim();
    if (name.isEmpty) return;
    _naming = true;
    try {
      await renameDevice(me, name);
    } on Object catch (e) {
      debugPrint('[vault] naming this device: $e');
    } finally {
      _naming = false;
    }
  }

  /// A sign-in made for one important request: linking, removing a device,
  /// deleting the account. The server wants it less than ten minutes old and
  /// bound to this device's key. Null when the person closed the sheet.
  Future<ProviderToken?> _freshToken(String provider) async {
    final nonce = await _keys.signinNonce();
    return switch (provider) {
      'google' => _signin.google(nonce),
      'apple' => _signin.apple(nonce),
      _ => throw ArgumentError.value(provider, 'provider'),
    };
  }

  /// Link a second sign-in to this Drive, another way back in. Linking Google
  /// also writes the key copy to its Drive app-data folder. False when the
  /// person closed the sheet. Throws [VaultApiException]
  /// (`VAULT_IDENTITY_IN_USE`: that account has its own Drive).
  Future<bool> link(String provider) async {
    final vaultId = _requireVault();
    final token = await _freshToken(provider);
    if (token == null) return false;
    await _api.linkIdentity(
      vaultId,
      provider: token.provider,
      idToken: token.idToken,
    );
    final vk = await _keys.vaultKey();
    final serverHalf = await _keys.serverHalf();
    if (vk != null && serverHalf != null) {
      await keyCopy.save(
        vaultId: vaultId,
        vaultKey: vk,
        serverHalf: serverHalf,
        interactive: provider == 'google',
      );
    }
    await refreshInfo();
    return true;
  }

  // ---- the recovery phrase (task 3.7) -----------------------------------------

  /// The 24 words that encode the vault key on this device. The caller shows
  /// them only after the device lock (DeviceLock).
  Future<String?> phrase() async {
    final vk = await _keys.vaultKey();
    return vk == null ? null : Rust.vaultPhraseFromKey(vk);
  }

  /// A device waiting for the key takes it from the phrase. Throws
  /// [VaultApiException] `VAULT_PHRASE_INVALID` for words that are not a
  /// phrase, `VAULT_KEY_MISMATCH` for another Drive's phrase.
  Future<void> acceptPhrase(String phrase) async {
    final Uint8List vk;
    try {
      vk = Rust.vaultKeyFromPhrase(
        phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' '),
      );
    } on Object {
      throw const VaultApiException(
        'VAULT_PHRASE_INVALID',
        'These words are not a recovery phrase',
      );
    }
    await acceptVaultKey(vk, await _keyCheck());
  }

  // ---- the key by QR code (task 3.8) -------------------------------------------

  /// A device waiting for the key: open a five-minute pairing slot and make
  /// the QR code another device of the same Drive scans.
  Future<VaultPairing> startPairing() async {
    _requireVault();
    final slot = await _api.openPairSlot();
    final key = Rust.vaultGrantKeyGenerate();
    return VaultPairing._(slot, key.secret, key.public);
  }

  /// Wait for the other device to leave the key in the slot. True once the
  /// key is here and checked; false when [cancelled] or the slot ran out.
  Future<bool> awaitGrant(
    VaultPairing pairing, {
    Duration every = const Duration(seconds: 2),
    Duration limit = const Duration(minutes: 5),
    bool Function()? cancelled,
  }) async {
    final vaultId = _requireVault();
    final keyCheck = await _keyCheck();
    final until = DateTime.now().add(limit);
    while (DateTime.now().isBefore(until)) {
      if (cancelled?.call() ?? false) return false;
      final ({Uint8List box, Uint8List granterPub, String vaultId})? got;
      try {
        got = await _api.takePairSlot(pairing.slot);
      } on VaultApiException catch (e) {
        if (e.code == 'VAULT_PAIR_NOT_FOUND') return false;
        if (e.code != 'NETWORK') rethrow;
        await Future<void>.delayed(every);
        continue;
      }
      if (got != null) {
        if (got.vaultId != vaultId) {
          throw const VaultApiException(
            'VAULT_KEY_MISMATCH',
            'That device belongs to another Drive',
          );
        }
        final Uint8List vk;
        try {
          vk = Rust.vaultAcceptGrant(
            vaultId: vaultId,
            mineSecret: pairing._secret,
            granterPub: got.granterPub,
            boxed: got.box,
            expectedKeyCheck: keyCheck,
          );
        } on Object {
          throw const VaultApiException(
            'VAULT_KEY_MISMATCH',
            'The key from that device does not fit this Drive',
          );
        }
        await acceptVaultKey(vk, keyCheck);
        return true;
      }
      await Future<void>.delayed(every);
    }
    return false;
  }

  /// A device with the key: hand it to the device whose QR code was scanned.
  /// The key in the code came from the camera, never from the server, so the
  /// server cannot swap it. Throws [FormatException] for a code that is not a
  /// Drive pairing code.
  Future<void> grantTo(String scanned) async {
    final vaultId = _requireVault();
    final code = VaultPairing.parse(scanned);
    final vk = await _keys.vaultKey();
    if (vk == null) {
      throw const VaultApiException(
        'VAULT_NO_KEY',
        'This device does not have the key yet',
      );
    }
    final mine = Rust.vaultGrantKeyGenerate();
    final box = Rust.vaultGrant(
      vaultKey: vk,
      vaultId: vaultId,
      mineSecret: mine.secret,
      newPub: code.publicKey,
    );
    await _api.fillPairSlot(
      vaultId,
      code.slot,
      box: box,
      granterPub: mine.public,
    );
  }

  // ---- deleting the account (task 3.9) ----------------------------------------

  /// Delete the Drive account: a fresh sign-in, the key copy removed from
  /// iCloud Keychain and Google Drive, then the account and every file on the
  /// server, then everything Drive on this device. Null when the person
  /// closed the sign-in sheet; otherwise the places the key copy could not be
  /// removed from (unreadable without the deleted server half, but the person
  /// should know).
  Future<List<String>?> deleteAccount(String provider) async {
    final vaultId = _requireVault();
    final token = await _freshToken(provider);
    if (token == null) return null;
    // The copy first: if the server call then fails, the account is still
    // there and the next start writes the copy again.
    final left = await keyCopy.deleteAll(
      vaultId,
      interactive: provider == 'google',
    );
    await _api.deleteAccount(
      vaultId,
      provider: token.provider,
      idToken: token.idToken,
    );
    await signOut();
    return left;
  }

  String _requireVault() {
    final id = _vaultId;
    if (id == null) {
      throw const VaultApiException(
        'VAULT_NOT_SIGNED_IN',
        'No Drive account on this device',
      );
    }
    return id;
  }

  Future<String> _keyCheck() async {
    final known = _last?.keyCheck ?? _info?['keyCheck'] as String?;
    if (known != null) return known;
    await refreshInfo();
    final fetched = _info?['keyCheck'] as String?;
    if (fetched == null) {
      throw const VaultApiException(
        'VAULT_NO_KEY',
        'This Drive has no key yet',
      );
    }
    return fetched;
  }

  /// Forget Drive on this device. The account and its files stay.
  Future<void> signOut() async {
    await _keys.forgetVault();
    await _signin.forgetGoogle();
    await _dao?.clearAll();
    await _onForget?.call();
    keyCopy.reset();
    _vaultId = null;
    _last = null;
    _info = null;
    _status = VaultStatus.signedOut;
    notifyListeners();
  }
}

/// One pairing slot opened by a device waiting for the key (task 3.8), and
/// the QR code it shows: `BSVP1.<slot>.<X25519 public key, base64url>`. Not a
/// URL on purpose: a system camera app has nothing to open, and only Drive's
/// own scanner reads it.
class VaultPairing {
  VaultPairing._(this.slot, this._secret, this.publicKey);

  final String slot;
  final Uint8List _secret;
  final Uint8List publicKey;

  static const _prefix = 'BSVP1';

  String get code =>
      '$_prefix.$slot.${base64Url.encode(publicKey).replaceAll('=', '')}';

  /// Read a scanned code. Throws [FormatException].
  static ({String slot, Uint8List publicKey}) parse(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 3 ||
        parts[0] != _prefix ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(parts[1])) {
      throw const FormatException('not a Drive pairing code');
    }
    final Uint8List key;
    try {
      key = base64Url.decode(base64Url.normalize(parts[2]));
    } on FormatException {
      throw const FormatException('not a Drive pairing code');
    }
    if (key.length != 32) {
      throw const FormatException('not a Drive pairing code');
    }
    return (slot: parts[1], publicKey: key);
  }
}

/// One device of the Drive, for the device list.
class VaultDeviceView {
  const VaultDeviceView({
    required this.id,
    required this.name,
    required this.thisDevice,
    required this.pending,
    required this.addedAt,
    required this.lastSeenAt,
  });

  final String id;

  /// Null until the device has been named (or when the name does not open).
  final String? name;
  final bool thisDevice;

  /// Maximum security: waiting for approval.
  final bool pending;
  final int addedAt;
  final int? lastSeenAt;
}
