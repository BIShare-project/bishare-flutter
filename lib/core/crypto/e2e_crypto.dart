import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../constants/protocol.dart';

/// End-to-end encryption engine — a byte-exact Dart port of the native
/// `BIShareEncryption` (CryptoKit / Kotlin / Rust). Interop is mandatory, so the
/// scheme is reproduced precisely:
///
/// * Key agreement: Curve25519 (X25519) ECDH; public keys are raw 32 bytes,
///   base64-encoded. Legacy 44-byte X.509 SPKI keys (old Android) are accepted
///   and normalised to their trailing 32 bytes.
/// * Key derivation: HKDF-SHA256, salt = "BIShare-E2E", info = "file-transfer",
///   32-byte output.
/// * Cipher: AES-256-GCM. Combined layout: `nonce(12) | ciphertext | tag(16)`.
/// * Streaming: a random 12-byte base nonce per file; each chunk's nonce is the
///   base nonce XOR'd with the big-endian chunk index in its last 8 bytes.
class E2ECrypto {
  E2ECrypto._(this._keyPair, this.publicKeyBytes);

  static final X25519 _x25519 = X25519();
  static final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: BIShareCrypto.aesKeySize,
  );

  /// 12-byte DER SubjectPublicKeyInfo header for X25519 (RFC 8410).
  static const List<int> _x509X25519Prefix = [
    0x30,
    0x2a,
    0x30,
    0x05,
    0x06,
    0x03,
    0x2b,
    0x65,
    0x6e,
    0x03,
    0x21,
    0x00,
  ];

  final SimpleKeyPair _keyPair;

  /// Our raw 32-byte public key.
  final Uint8List publicKeyBytes;

  /// Base64 of our raw public key — this is what goes into `DeviceInfo.publicKey`.
  String get publicKeyBase64 => base64.encode(publicKeyBytes);

  /// Load an identity from a stored 32-byte private seed, or generate a new one.
  /// Returns the (engine, privateSeed) pair so the app can persist the seed.
  static Future<(E2ECrypto engine, Uint8List seed)> create({
    Uint8List? privateSeed,
  }) async {
    final SimpleKeyPair keyPair;
    if (privateSeed != null && privateSeed.length == 32) {
      keyPair = await _x25519.newKeyPairFromSeed(privateSeed);
    } else {
      keyPair = await _x25519.newKeyPair();
    }
    final pub = await keyPair.extractPublicKey();
    final seedData = await keyPair.extractPrivateKeyBytes();
    return (
      E2ECrypto._(keyPair, Uint8List.fromList(pub.bytes)),
      Uint8List.fromList(seedData),
    );
  }

  /// Normalise a peer key to raw 32 bytes (accepts raw 32 and legacy 44-byte SPKI).
  static Uint8List? normalizeRawKey(List<int> data) {
    if (data.length == 32) return Uint8List.fromList(data);
    if (data.length == 44 &&
        _listEquals(data.sublist(0, 12), _x509X25519Prefix)) {
      return Uint8List.fromList(data.sublist(12));
    }
    return null;
  }

  /// Derive a per-peer AES-256 session key via ECDH + HKDF. Returns null if the
  /// peer key is malformed.
  Future<SessionCipher?> deriveSession(String peerPublicKeyBase64) async {
    final decoded = _tryBase64(peerPublicKeyBase64);
    if (decoded == null) return null;
    final raw = normalizeRawKey(decoded);
    if (raw == null) return null;

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(raw, type: KeyPairType.x25519),
    );
    final aesKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(BIShareCrypto.e2eSalt), // HKDF salt
      info: utf8.encode(BIShareCrypto.e2eInfo),
    );
    return SessionCipher._(aesKey);
  }

  /// Visual fingerprint of a peer's base64 public key, e.g. "A1 B2 C3 …" (8 bytes).
  static Future<String> peerFingerprint(String base64Key) async {
    final decoded = _tryBase64(base64Key);
    if (decoded == null) return '—';
    final raw = normalizeRawKey(decoded);
    if (raw == null) return '—';
    return _fingerprintOf(raw);
  }

  /// Our own key fingerprint.
  Future<String> get keyFingerprint => _fingerprintOf(publicKeyBytes);

  static Future<String> _fingerprintOf(List<int> keyBytes) async {
    final hash = await Sha256().hash(keyBytes);
    return hash.bytes
        .take(BIShareCrypto.fingerprintBytes)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  static Uint8List? _tryBase64(String s) {
    try {
      return Uint8List.fromList(base64.decode(s));
    } on FormatException {
      return null;
    }
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// An established AES-256-GCM session for one peer.
class SessionCipher {
  SessionCipher._(this._key);
  final SecretKey _key;

  static final AesGcm _aes = AesGcm.with256bits(
    nonceLength: BIShareCrypto.gcmNonceSize,
  );

  /// Generate a random 12-byte base nonce for a file transfer session.
  static Uint8List generateBaseNonce() => Uint8List.fromList(
    _aes.newNonce().sublist(0, BIShareCrypto.gcmNonceSize),
  );

  /// Derive a chunk nonce: baseNonce XOR bigEndian(chunkIndex) into last 8 bytes.
  static Uint8List _chunkNonce(Uint8List baseNonce, int chunkIndex) {
    final n = Uint8List.fromList(baseNonce);
    final idx = ByteData(8)..setUint64(0, chunkIndex);
    for (var i = 0; i < 8; i++) {
      n[4 + i] ^= idx.getUint8(i);
    }
    return n;
  }

  /// Encrypt one chunk → `nonce(12) | ciphertext | tag(16)`.
  Future<Uint8List> encryptChunk(
    List<int> data,
    int chunkIndex,
    Uint8List baseNonce,
  ) async {
    final nonce = _chunkNonce(baseNonce, chunkIndex);
    final box = await _aes.encrypt(data, secretKey: _key, nonce: nonce);
    return _combine(box);
  }

  /// Decrypt one chunk from combined form, verifying the embedded nonce matches
  /// the deterministically-derived one (matches native's extra safety check).
  Future<Uint8List> decryptChunk(
    Uint8List combined,
    int chunkIndex,
    Uint8List baseNonce,
  ) async {
    final expected = _chunkNonce(baseNonce, chunkIndex);
    final box = _split(combined);
    if (!E2ECrypto._listEquals(box.nonce, expected)) {
      throw const FormatException('chunk nonce mismatch');
    }
    final clear = await _aes.decrypt(box, secretKey: _key);
    return Uint8List.fromList(clear);
  }

  /// Encrypt a whole buffer with a random nonce (native `encrypt(data:)`).
  Future<Uint8List> encryptCombined(List<int> data) async {
    final box = await _aes.encrypt(data, secretKey: _key);
    return _combine(box);
  }

  /// Decrypt a whole buffer from combined form.
  Future<Uint8List> decryptCombined(Uint8List combined) async {
    final clear = await _aes.decrypt(_split(combined), secretKey: _key);
    return Uint8List.fromList(clear);
  }

  static Uint8List _combine(SecretBox box) {
    final out = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  static SecretBox _split(Uint8List combined) {
    const nonceLen = BIShareCrypto.gcmNonceSize;
    const tagLen = BIShareCrypto.gcmTagBytes;
    if (combined.length < nonceLen + tagLen) {
      throw const FormatException('ciphertext too short');
    }
    final nonce = combined.sublist(0, nonceLen);
    final tag = combined.sublist(combined.length - tagLen);
    final cipher = combined.sublist(nonceLen, combined.length - tagLen);
    return SecretBox(cipher, nonce: nonce, mac: Mac(tag));
  }
}
