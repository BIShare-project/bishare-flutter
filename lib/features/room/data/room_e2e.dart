import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// End-to-end encryption for Cloud rooms, v1 — the app side of the scheme
/// the web client defines in `bishare-web/src/lib/rooms/e2e.ts`. Both are
/// pinned by the same golden vectors (`test/fixtures/room_e2e_vectors.json`,
/// generated from the web code), so an app member and a browser member hand
/// each other keys and open each other's files byte for byte.
///
/// A room is joined by typing a code, so unlike a transfer link there is no
/// fragment to carry a key. Instead the creator's device makes the room key
/// and members pass it on, sealed to each newcomer's X25519 public key and
/// relayed by the room's Durable Object — which only ever sees public keys,
/// sealed boxes and BSE2 ciphertext.
///
///   b64u(x)  = base64url without padding;  HKDF = HKDF-SHA256
///   Room key K    32 random bytes
///   kid           b64u(HKDF(K, salt = 32×0x00, "bishare-room-kid-v1", 16))
///   Per file      S = 16 random bytes (X-Enc-Salt = b64u(S))
///     fileKey     HKDF(K, S, "bishare-room-file-v1", 32) → BSE2 key
///     metaKey     HKDF(K, S, "bishare-room-meta-v1", 32)
///     X-Enc-Meta  b64u(nonce12 ‖ AES-256-GCM(metaKey, nonce,
///                   utf8(JSON {n, t, s, th?}), aad = "bishare-room-meta-v1"))
///   Hand-off      shared  = X25519(myPriv, theirPub), refused if all zero
///                 wrapKey = HKDF(shared, joinerPub ‖ granterPub, "bishare-room-grant-v1", 32)
///                 box     = b64u(nonce12 ‖ AES-256-GCM(wrapKey, nonce, K, aad = roomCode))
abstract final class RoomE2E {
  static const int version = 1;

  /// What an encrypted upload calls itself on the wire; the real name is sealed.
  static const String sealedName = 'encrypted.bse2';

  static const _kidInfo = 'bishare-room-kid-v1';
  static const _fileInfo = 'bishare-room-file-v1';
  static const _metaInfo = 'bishare-room-meta-v1';
  static const _grantInfo = 'bishare-room-grant-v1';

  static final _aes = AesGcm.with256bits();
  static final _x25519 = X25519();
  static final _rng = Random.secure();

  // ── encoding ────────────────────────────────────────────────────────────

  static String b64u(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List fromB64u(String s) {
    final padded = s.padRight(s.length + (4 - s.length % 4) % 4, '=');
    return Uint8List.fromList(base64Url.decode(padded));
  }

  static Uint8List random(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  // ── primitives ──────────────────────────────────────────────────────────

  static Future<Uint8List> _hkdf(
    List<int> ikm,
    List<int> salt,
    String info,
    int length,
  ) async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
      secretKey: SecretKey(ikm),
      nonce: salt,
      info: utf8.encode(info),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Future<Uint8List> _seal(
    List<int> key,
    List<int> plain,
    String aad, {
    List<int>? nonce,
  }) async {
    final n = nonce ?? random(12);
    final box = await _aes.encrypt(
      plain,
      secretKey: SecretKey(key),
      nonce: n,
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList([...n, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> _open(List<int> key, Uint8List sealed, String aad) async {
    if (sealed.length < 12 + 16) throw const RoomKeyException('sealed box too short');
    try {
      final plain = await _aes.decrypt(
        SecretBox(
          sealed.sublist(12, sealed.length - 16),
          nonce: sealed.sublist(0, 12),
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: utf8.encode(aad),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const RoomKeyException('could not open sealed box');
    }
  }

  // ── room key ────────────────────────────────────────────────────────────

  static Uint8List newRoomKey() => random(32);

  static Future<String> keyId(List<int> roomKey) async =>
      b64u(await _hkdf(roomKey, Uint8List(32), _kidInfo, 16));

  // ── files ───────────────────────────────────────────────────────────────

  static Future<({Uint8List fileKey, Uint8List metaKey})> fileKeys(
    List<int> roomKey,
    List<int> salt,
  ) async {
    final keys = await Future.wait([
      _hkdf(roomKey, salt, _fileInfo, 32),
      _hkdf(roomKey, salt, _metaInfo, 32),
    ]);
    return (fileKey: keys[0], metaKey: keys[1]);
  }

  /// The X-Enc-Salt / X-Enc-Meta headers for an upload, and the BSE2 key
  /// for its bytes. [salt] and [nonce] are fixed only by tests.
  static Future<SealedRoomFile> sealFile(
    List<int> roomKey,
    RoomFileMeta meta, {
    List<int>? salt,
    List<int>? nonce,
  }) async {
    final s = salt ?? random(16);
    final keys = await fileKeys(roomKey, s);
    // Key order n, t, s, th — the same JSON bytes the web writes.
    final json = jsonEncode({
      'n': meta.name,
      't': meta.type,
      's': meta.size,
      if (meta.thumbnail != null && meta.thumbnail!.isNotEmpty) 'th': meta.thumbnail,
    });
    final box = await _seal(keys.metaKey, utf8.encode(json), _metaInfo, nonce: nonce);
    return SealedRoomFile(salt: b64u(s), meta: b64u(box), fileKey: keys.fileKey);
  }

  /// Metadata and BSE2 key for a file someone sealed. Throws
  /// [RoomKeyException] when the key doesn't open it.
  static Future<({RoomFileMeta meta, Uint8List fileKey})> openFile(
    List<int> roomKey,
    String saltB64,
    String metaB64,
  ) async {
    final keys = await fileKeys(roomKey, fromB64u(saltB64));
    final plain = await _open(keys.metaKey, fromB64u(metaB64), _metaInfo);
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const RoomKeyException('sealed metadata is not JSON');
    }
    final m = j is Map ? j : const <String, Object?>{};
    final n = m['n'];
    final t = m['t'];
    final s = m['s'];
    final th = m['th'];
    return (
      meta: RoomFileMeta(
        name: n is String && n.isNotEmpty ? n : 'file',
        type: t is String && t.isNotEmpty ? t : 'application/octet-stream',
        size: s is num ? s.toInt() : 0,
        thumbnail: th is String && th.isNotEmpty ? th : null,
      ),
      fileKey: keys.fileKey,
    );
  }

  // ── hand-off ────────────────────────────────────────────────────────────

  /// A fresh X25519 pair for one join. [seed] is fixed only by tests.
  static Future<RoomKeyPair> newKeyPair({List<int>? seed}) async {
    final kp = seed == null
        ? await _x25519.newKeyPair()
        : await _x25519.newKeyPairFromSeed(seed);
    final pub = await kp.extractPublicKey();
    return RoomKeyPair._(kp, Uint8List.fromList(pub.bytes));
  }

  static Future<Uint8List> _wrapKey(
    RoomKeyPair mine,
    List<int> theirPub,
    List<int> joinerPub,
    List<int> granterPub,
  ) async {
    if (theirPub.length != 32) throw const RoomKeyException('bad public key');
    final shared = await (await _x25519.sharedSecretKey(
      keyPair: mine._pair,
      remotePublicKey: SimplePublicKey(theirPub, type: KeyPairType.x25519),
    )).extractBytes();
    if (shared.every((b) => b == 0)) throw const RoomKeyException('bad public key');
    return _hkdf(shared, [...joinerPub, ...granterPub], _grantInfo, 32);
  }

  /// A member who holds K seals it for a joiner.
  static Future<String> grant(
    List<int> roomKey,
    String roomCode,
    RoomKeyPair mine,
    String joinerPubB64, {
    List<int>? nonce,
  }) async {
    final joinerPub = fromB64u(joinerPubB64);
    final wrap = await _wrapKey(mine, joinerPub, joinerPub, mine.publicKey);
    return b64u(await _seal(wrap, roomKey, roomCode, nonce: nonce));
  }

  /// The joiner opens a grant and accepts K only if it matches the room's kid.
  static Future<Uint8List> acceptGrant(
    String roomCode,
    RoomKeyPair mine,
    String granterPubB64,
    String boxB64,
    String expectedKid,
  ) async {
    final granterPub = fromB64u(granterPubB64);
    final wrap = await _wrapKey(mine, granterPub, mine.publicKey, granterPub);
    final key = await _open(wrap, fromB64u(boxB64), roomCode);
    if (key.length != 32 || await keyId(key) != expectedKid) {
      throw const RoomKeyException('key does not belong to this room');
    }
    return key;
  }
}

class RoomKeyException implements Exception {
  const RoomKeyException(this.message);
  final String message;

  @override
  String toString() => 'RoomKeyException: $message';
}

/// What an encrypted room seals about each file.
class RoomFileMeta {
  const RoomFileMeta({
    required this.name,
    required this.type,
    required this.size,
    this.thumbnail,
  });

  final String name;
  final String type;
  final int size;
  final String? thumbnail; // JPEG, base64
}

class SealedRoomFile {
  const SealedRoomFile({required this.salt, required this.meta, required this.fileKey});
  final String salt; // X-Enc-Salt
  final String meta; // X-Enc-Meta
  final Uint8List fileKey; // BSE2 key for the bytes
}

class RoomKeyPair {
  RoomKeyPair._(this._pair, this.publicKey);
  final SimpleKeyPair _pair;
  final Uint8List publicKey;
  String get publicKeyB64 => RoomE2E.b64u(publicKey);
}
