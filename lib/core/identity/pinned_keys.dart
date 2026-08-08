import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Trust-on-first-use pinning of peer public keys, keyed by device fingerprint.
///
/// Closes the auto-accept hole (P0): a favorited device is auto-accepted only if
/// it still presents the same X25519 key we pinned the first time we saw it. A
/// changed key — a replaced device, or an active MITM substituting its own key —
/// fails the match, so the transfer falls back to a manual accept prompt instead
/// of being silently auto-accepted. Fail-safe: the worst case is a legitimate
/// device needing one manual accept.
///
/// Storage is a plain SharedPreferences JSON map (fingerprint → base64 pubkey),
/// so there is no drift schema/migration. Fingerprints are the peer's
/// self-asserted id, so this is TOFU: it detects a *later* key change for a known
/// device, not a MITM already present at the very first contact — that needs
/// out-of-band verification (safety number / QR), a planned follow-up.
class PinnedKeysStore {
  PinnedKeysStore(this._prefs) {
    final raw = _prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _pins = {
          for (final e in map.entries)
            if (e.value is String) e.key: e.value as String,
        };
      } on Object {
        _pins = {};
      }
    }
  }

  static const _prefsKey = 'pinnedPeerKeys';

  final SharedPreferences _prefs;
  Map<String, String> _pins = {};

  /// The pinned public key for [fingerprint], or null if none is pinned yet.
  String? pinnedKey(String fingerprint) => _pins[fingerprint];

  /// Whether a key is already pinned for [fingerprint].
  bool isPinned(String fingerprint) => _pins.containsKey(fingerprint);

  /// Records [publicKey] for [fingerprint] on first sight (TOFU) and reports
  /// whether it matches what was pinned. Returns:
  ///  - `true`  when nothing was pinned yet (pins it now) or the key matches;
  ///  - `false` when [publicKey] is empty, or it differs from the pinned key.
  /// A mismatch does NOT overwrite the pin — the change must be reviewed first.
  Future<bool> recordAndMatch(String fingerprint, String? publicKey) async {
    if (publicKey == null || publicKey.isEmpty) return false;
    final existing = _pins[fingerprint];
    if (existing == null) {
      _pins[fingerprint] = publicKey;
      await _persist();
      return true;
    }
    return existing == publicKey;
  }

  /// Replace the pinned key for [fingerprint] — used after the user explicitly
  /// verifies/accepts a key change (safety-number compare, or a manual accept).
  Future<void> repin(String fingerprint, String publicKey) async {
    if (publicKey.isEmpty) return;
    _pins[fingerprint] = publicKey;
    await _persist();
  }

  Future<void> _persist() => _prefs.setString(_prefsKey, jsonEncode(_pins));
}
