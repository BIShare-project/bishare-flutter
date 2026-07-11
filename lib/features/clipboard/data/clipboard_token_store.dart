import 'dart:typed_data';

import 'package:uuid/uuid.dart';

/// A staged clipboard payload awaiting a pull (see [ClipboardTokenStore]).
class ClipboardShare {
  const ClipboardShare({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

/// One-shot pull tokens for the binary clipboard flow (plan §1): when an image
/// is copied, the sender stages the bytes here and announces a token over the
/// existing UDP clipboard datagram; a v2.4 receiver pulls them back with
/// `GET /api/v1/clipboard?token=…` on the transfer server.
///
/// Token semantics (per spec): 60s TTL, SINGLE-USE (consumed by the first
/// successful [take]), constant-time token comparison. Because a copy is
/// announced to every capable peer and tokens are one-shot, the service mints
/// one token PER PEER for the same staged bytes — so a second receiver on the
/// LAN can't be starved by the first one's pull.
///
/// Separated from `TransferServer` so the route's gate logic is unit-testable
/// (the server itself needs a `DeviceIdentity`, which can't be built in tests).
class ClipboardTokenStore {
  ClipboardTokenStore({
    this.ttl = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// How long a published token stays valid.
  final Duration ttl;
  final DateTime Function() _now;
  final _uuid = const Uuid();

  final Map<String, _Entry> _entries = {};

  /// Stage [share] and mint its one-shot token.
  String publish(ClipboardShare share) {
    _prune();
    final token = _uuid.v4();
    _entries[token] = _Entry(share: share, expires: _now().add(ttl));
    return token;
  }

  /// Redeem [token]: returns the staged payload and consumes the token, or
  /// null (unknown / already used / expired). Comparison is constant-time per
  /// stored token so timing can't leak byte-by-byte matches.
  ClipboardShare? take(String token) {
    _prune();
    String? hit;
    for (final key in _entries.keys) {
      // No early exit on the first mismatching byte (constant-time compare);
      // scanning all entries also keeps "which token matched" timing-flat.
      if (_constantTimeEquals(key, token)) hit = key;
    }
    if (hit == null) return null;
    return _entries.remove(hit)?.share;
  }

  /// Drop everything (e.g. when clipboard sync is switched off).
  void clear() => _entries.clear();

  void _prune() {
    final now = _now();
    _entries.removeWhere((_, e) => e.expires.isBefore(now));
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class _Entry {
  const _Entry({required this.share, required this.expires});

  final ClipboardShare share;
  final DateTime expires;
}
