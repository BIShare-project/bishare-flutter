/// Cloud-path E2E crypto for folder sync (§7.1). Blobs and manifests are
/// encrypted CLIENT-SIDE under the pair's 32-byte AES key; the backend only
/// ever stores ciphertext.
///
/// Blob scheme — content-addressed over ciphertext:
/// * base nonce = HKDF-SHA256(salt "bishare-sync-blob-nonce", ikm pairKey,
///   info plaintextSha256Hex)[..12] — DETERMINISTIC, so the same content
///   re-encrypts byte-identically (check-exists dedup + idempotent retry stay
///   alive) while distinct content can never reuse a (key, nonce) pair. This
///   mirrors the Rust `derive_blob_base_nonce` exactly (M0 proof tests).
/// * body = repeat [u32 BE frameLen][nonce(12) | ct | tag(16)] — 256 KiB
///   plaintext chunks with the v2.2 chunk-nonce derivation (baseNonce XOR
///   big-endian chunkIndex in the last 8 bytes), byte-compatible with the Rust
///   `encrypt_chunk` the LAN path uses.
///
/// Manifests are small: one AES-256-GCM pass with a RANDOM nonce
/// (`nonce | ct | tag`).
///
/// This implementation is pure Dart (package:cryptography — the same
/// interop-proven stack as `E2ECrypto`), fast enough for manifests and typical
/// blobs; an FFI-backed variant can swap in later for very large files without
/// changing the format.
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SyncCryptoException implements Exception {
  const SyncCryptoException(this.message);
  final String message;
  @override
  String toString() => 'SyncCryptoException: $message';
}

class SyncBlobCipher {
  SyncBlobCipher();

  static const int chunkSize = 256 * 1024;
  static const int nonceLen = 12;
  static const int tagLen = 16;

  final AesGcm _aes = AesGcm.with256bits(nonceLength: nonceLen);
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: nonceLen);

  /// Deterministic 12-byte base nonce — the Dart mirror of the Rust
  /// `derive_blob_base_nonce(pair_key, plaintext_sha256_hex)`.
  Future<Uint8List> deriveBlobBaseNonce(
    Uint8List pairKey,
    String plaintextSha256Hex,
  ) async {
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(pairKey),
      nonce: 'bishare-sync-blob-nonce'.codeUnits, // HKDF salt
      info: plaintextSha256Hex.codeUnits,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Uint8List _chunkNonce(Uint8List base, int index) {
    final n = Uint8List.fromList(base);
    final idx = ByteData(8)..setUint64(0, index);
    for (var i = 0; i < 8; i++) {
      n[4 + i] ^= idx.getUint8(i);
    }
    return n;
  }

  /// Encrypt a whole blob. Deterministic in (pairKey, content).
  Future<Uint8List> encryptBlob(
    Uint8List plain,
    Uint8List pairKey,
    String plaintextSha256Hex,
  ) async {
    _requireKey(pairKey);
    final base = await deriveBlobBaseNonce(pairKey, plaintextSha256Hex);
    final key = SecretKey(pairKey);
    final out = BytesBuilder(copy: false);
    var index = 0;
    for (var off = 0; off < plain.length || index == 0; off += chunkSize) {
      final end =
          (off + chunkSize < plain.length) ? off + chunkSize : plain.length;
      final nonce = _chunkNonce(base, index);
      final box = await _aes.encrypt(
        plain.sublist(off, end),
        secretKey: key,
        nonce: nonce,
      );
      final frame = BytesBuilder(copy: false)
        ..add(nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
      final bytes = frame.toBytes();
      final len = ByteData(4)..setUint32(0, bytes.length);
      out
        ..add(len.buffer.asUint8List())
        ..add(bytes);
      index++;
      if (plain.isEmpty) break; // a single empty frame authenticates emptiness
    }
    return out.toBytes();
  }

  /// Decrypt + authenticate a blob (verifies every chunk nonce against the
  /// derived sequence — a reordered/foreign frame fails closed).
  Future<Uint8List> decryptBlob(
    Uint8List cipher,
    Uint8List pairKey,
    String plaintextSha256Hex,
  ) async {
    _requireKey(pairKey);
    final base = await deriveBlobBaseNonce(pairKey, plaintextSha256Hex);
    final key = SecretKey(pairKey);
    final out = BytesBuilder(copy: false);
    var offset = 0;
    var index = 0;
    final bd = ByteData.sublistView(cipher);
    while (offset < cipher.length) {
      if (offset + 4 > cipher.length) {
        throw const SyncCryptoException('truncated frame length');
      }
      final frameLen = bd.getUint32(offset);
      offset += 4;
      if (frameLen < nonceLen + tagLen || offset + frameLen > cipher.length) {
        throw const SyncCryptoException('malformed frame');
      }
      final frame = cipher.sublist(offset, offset + frameLen);
      offset += frameLen;
      final nonce = frame.sublist(0, nonceLen);
      final expected = _chunkNonce(base, index);
      for (var i = 0; i < nonceLen; i++) {
        if (nonce[i] != expected[i]) {
          throw const SyncCryptoException('chunk nonce mismatch');
        }
      }
      final clear = await _aes.decrypt(
        SecretBox(
          frame.sublist(nonceLen, frameLen - tagLen),
          nonce: nonce,
          mac: Mac(frame.sublist(frameLen - tagLen)),
        ),
        secretKey: key,
      );
      out.add(clear);
      index++;
    }
    return out.toBytes();
  }

  /// Encrypt a manifest (small JSON) with a RANDOM nonce → `nonce | ct | tag`.
  Future<Uint8List> encryptManifest(Uint8List plain, Uint8List pairKey) async {
    _requireKey(pairKey);
    final box = await _aes.encrypt(plain, secretKey: SecretKey(pairKey));
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> decryptManifest(
    Uint8List cipher,
    Uint8List pairKey,
  ) async {
    _requireKey(pairKey);
    if (cipher.length < nonceLen + tagLen) {
      throw const SyncCryptoException('manifest too short');
    }
    final clear = await _aes.decrypt(
      SecretBox(
        cipher.sublist(nonceLen, cipher.length - tagLen),
        nonce: cipher.sublist(0, nonceLen),
        mac: Mac(cipher.sublist(cipher.length - tagLen)),
      ),
      secretKey: SecretKey(pairKey),
    );
    return Uint8List.fromList(clear);
  }

  void _requireKey(Uint8List pairKey) {
    if (pairKey.length != 32) {
      throw const SyncCryptoException('pairKey must be 32 bytes');
    }
  }
}
