import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/rust/rust_facade.dart';
import 'google_app_data.dart';

/// The key copy cannot be reached from here without the person (no Google
/// sign-in on this device, or consent not given yet).
class KeyCopyUnreachable implements Exception {
  const KeyCopyUnreachable(this.holder);
  final String holder;
  @override
  String toString() => 'KeyCopyUnreachable($holder)';
}

/// One place outside this device where the key copy can live
/// (drive-plan.md "Where the key copy lives").
abstract class KeyCopyHolder {
  /// "google" or "icloud".
  String get id;

  /// The copy, or null when there is none. Throws [KeyCopyUnreachable].
  Future<Uint8List?> read(String vaultId, {bool interactive = false});

  /// Throws [KeyCopyUnreachable].
  Future<void> write(
    String vaultId,
    Uint8List copy, {
    bool interactive = false,
  });

  /// Throws [KeyCopyUnreachable].
  Future<void> delete(String vaultId, {bool interactive = false});
}

/// An iCloud Keychain item: synchronised to the person's other Apple devices
/// with the same Apple ID when iCloud Keychain is on. The app cannot tell
/// whether it has synced.
class ICloudKeyCopyHolder implements KeyCopyHolder {
  ICloudKeyCopyHolder([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Its own service name, so it never mixes with the
            // this-device-only items of VaultKeyStore.
            iOptions: IOSOptions(
              accountName: 'app.bishare.vault.keycopy',
              accessibility: KeychainAccessibility.first_unlock,
              synchronizable: true,
            ),
            mOptions: MacOsOptions(
              accountName: 'app.bishare.vault.keycopy',
              accessibility: KeychainAccessibility.first_unlock,
              synchronizable: true,
            ),
          );

  final FlutterSecureStorage _storage;

  static bool get available => Platform.isIOS || Platform.isMacOS;

  @override
  String get id => 'icloud';

  static String _key(String vaultId) => 'vault.keyCopy.$vaultId';

  @override
  Future<Uint8List?> read(String vaultId, {bool interactive = false}) async {
    final v = await _storage.read(key: _key(vaultId));
    if (v == null || v.isEmpty) return null;
    try {
      return base64Url.decode(base64Url.normalize(v));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(
    String vaultId,
    Uint8List copy, {
    bool interactive = false,
  }) => _storage.write(
    key: _key(vaultId),
    value: base64Url.encode(copy).replaceAll('=', ''),
  );

  @override
  Future<void> delete(String vaultId, {bool interactive = false}) =>
      _storage.delete(key: _key(vaultId));
}

/// A file in the hidden app-data folder of the person's Google Drive.
class GoogleKeyCopyHolder implements KeyCopyHolder {
  GoogleKeyCopyHolder(this._appData);

  final GoogleAppData _appData;

  @override
  String get id => 'google';

  static String _name(String vaultId) => 'vault-$vaultId.key';

  Future<T> _reach<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on GoogleAuthNeeded {
      throw KeyCopyUnreachable(id);
    }
  }

  @override
  Future<Uint8List?> read(String vaultId, {bool interactive = false}) =>
      _reach(() => _appData.read(_name(vaultId), interactive: interactive));

  @override
  Future<void> write(
    String vaultId,
    Uint8List copy, {
    bool interactive = false,
  }) => _reach(
    () => _appData.write(_name(vaultId), copy, interactive: interactive),
  );

  @override
  Future<void> delete(String vaultId, {bool interactive = false}) =>
      _reach(() => _appData.delete(_name(vaultId), interactive: interactive));
}

/// What this device last saw of the key copy in one place.
enum KeyCopyState {
  /// Not looked at on this run.
  unknown,

  /// There, and it opens to this vault's key (for Google: read back).
  saved,

  /// Not there (for iCloud Keychain: maybe not synced yet).
  missing,

  /// Could not be reached without the person (Google not signed in here).
  unreachable,

  /// The place answered with an error; tried again at the next start.
  failed,
}

/// The key copy (drive-plan.md task 3.6): `VK` sealed with the server half
/// (VAULT-SPEC "Key copy") and kept in the person's own Apple or Google
/// account, so a new device that signs in gets the key with nothing typed or
/// scanned.
///
/// Neither place can open the copy: it needs the server half, which the
/// server hands only to a device that has just signed in. Every copy read is
/// checked against the account's key check before it is used.
class VaultKeyCopy extends ChangeNotifier {
  VaultKeyCopy(List<KeyCopyHolder> holders) : _holders = holders;

  final List<KeyCopyHolder> _holders;
  final Map<String, KeyCopyState> _state = {};

  /// The holders this device can use, in the order they are tried.
  List<String> get holders => [for (final h in _holders) h.id];

  KeyCopyState stateOf(String holder) => _state[holder] ?? KeyCopyState.unknown;

  /// Write the copy to every place, then read it back. [interactive] lets
  /// Google ask for consent, which only happens right after a tap.
  Future<void> save({
    required String vaultId,
    required Uint8List vaultKey,
    required Uint8List serverHalf,
    bool interactive = false,
  }) async {
    final copy = Rust.vaultSealKeyCopy(
      serverHalf: serverHalf,
      vaultId: vaultId,
      vaultKey: vaultKey,
    );
    for (final h in _holders) {
      await _guard(h, () async {
        await h.write(vaultId, copy, interactive: interactive);
        return _readBack(h, vaultId, serverHalf, vaultKey);
      });
    }
  }

  /// At start, on a device that has the key: every place still holds a copy
  /// that opens to it, and gets one again where it does not (the person
  /// cleared it, or disconnected BIShare from Google and connected again).
  Future<void> repair({
    required String vaultId,
    required Uint8List vaultKey,
    required Uint8List serverHalf,
  }) async {
    Uint8List? copy;
    for (final h in _holders) {
      await _guard(h, () async {
        final have = await h.read(vaultId);
        if (have != null &&
            _opens(have, vaultId, serverHalf, vaultKey: vaultKey)) {
          return KeyCopyState.saved;
        }
        copy ??= Rust.vaultSealKeyCopy(
          serverHalf: serverHalf,
          vaultId: vaultId,
          vaultKey: vaultKey,
        );
        await h.write(vaultId, copy!);
        return _readBack(h, vaultId, serverHalf, vaultKey);
      });
    }
  }

  /// The vault key from the first place whose copy opens and matches
  /// [keyCheck], or null when none does (yet: iCloud Keychain may not have
  /// synced).
  Future<Uint8List?> restore({
    required String vaultId,
    required Uint8List serverHalf,
    required String keyCheck,
    bool interactive = false,
  }) async {
    for (final h in _holders) {
      Uint8List? found;
      await _guard(h, () async {
        final copy = await h.read(vaultId, interactive: interactive);
        if (copy == null) return KeyCopyState.missing;
        final vk = _open(copy, vaultId, serverHalf);
        if (vk == null || Rust.vaultKeyCheck(vk) != keyCheck) {
          return KeyCopyState.failed;
        }
        found = vk;
        return KeyCopyState.saved;
      });
      if (found != null) return found;
    }
    return null;
  }

  /// Remove the copy from every place (account deleted). Google may need the
  /// person, so this runs right after the tap that confirms the deletion.
  /// Returns the holders that could not be cleared.
  Future<List<String>> deleteAll(
    String vaultId, {
    bool interactive = false,
  }) async {
    final left = <String>[];
    for (final h in _holders) {
      try {
        await h.delete(vaultId, interactive: interactive);
        _state.remove(h.id);
      } on Object catch (e) {
        debugPrint('[vault] key copy delete in ${h.id} failed: $e');
        left.add(h.id);
      }
    }
    notifyListeners();
    return left;
  }

  /// Forget what was seen on this run (sign-out).
  void reset() {
    _state.clear();
    notifyListeners();
  }

  /// Run one holder's step, record its state, never throw: a key copy that
  /// cannot be written must not stop a sign-in.
  Future<void> _guard(
    KeyCopyHolder h,
    Future<KeyCopyState> Function() step,
  ) async {
    KeyCopyState next;
    try {
      next = await step();
    } on KeyCopyUnreachable {
      next = KeyCopyState.unreachable;
    } on Object catch (e) {
      debugPrint('[vault] key copy in ${h.id}: $e');
      next = KeyCopyState.failed;
    }
    _state[h.id] = next;
    notifyListeners();
  }

  /// Read what was just written: a write is only "saved" once it reads back
  /// and opens to the same key.
  static Future<KeyCopyState> _readBack(
    KeyCopyHolder h,
    String vaultId,
    Uint8List serverHalf,
    Uint8List vaultKey,
  ) async {
    final back = await h.read(vaultId);
    return back != null && _opens(back, vaultId, serverHalf, vaultKey: vaultKey)
        ? KeyCopyState.saved
        : KeyCopyState.failed;
  }

  static Uint8List? _open(
    Uint8List copy,
    String vaultId,
    Uint8List serverHalf,
  ) {
    try {
      return Rust.vaultOpenKeyCopy(
        serverHalf: serverHalf,
        vaultId: vaultId,
        keyCopy: copy,
      );
    } on Object {
      return null;
    }
  }

  static bool _opens(
    Uint8List copy,
    String vaultId,
    Uint8List serverHalf, {
    required Uint8List vaultKey,
  }) {
    final vk = _open(copy, vaultId, serverHalf);
    return vk != null && listEquals(vk, vaultKey);
  }
}
