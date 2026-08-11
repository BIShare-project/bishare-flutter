import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Decryptor for the web client's end-to-end-encrypted cloud transfers —
/// a byte-exact Dart port of `bishare-web/src/lib/e2e/crypto.ts` (read side).
///
/// Container format ("BSE2" v1):
///   header (24 bytes):
///     [0..4)   magic  = "BSE2"
///     [4]      version = 1
///     [5..8)   reserved (0)
///     [8..12)  salt (4 random bytes, folded into every nonce)
///     [12..16) recordSize (uint32 BE, plaintext bytes per record)
///     [16..24) plaintextSize (uint64 BE)
///   then back-to-back records, record i:
///     AES-256-GCM(plaintext[i*RS ...], iv = salt ‖ u64BE(i), aad = u32BE(i))
///     — each record's ciphertext is its plaintext length + 16-byte tag.
///
/// The record index in both the nonce and the AAD makes reorder/replace fail
/// authentication; plaintextSize pins the total so truncation is detected.
///
/// The 32-byte key rides in the share link's URL fragment (`#k=<base64url>`),
/// which browsers never send to the server — so the relay only ever stores
/// ciphertext, and the app must decrypt after downloading.
class Bse2Exception implements Exception {
  const Bse2Exception(this.message);
  final String message;

  @override
  String toString() => 'Bse2Exception: $message';
}

abstract final class Bse2 {
  static const List<int> magic = [0x42, 0x53, 0x45, 0x32]; // "BSE2"
  static const int version = 1;
  static const int headerSize = 24;
  static const int tagSize = 16;

  /// Largest record size we accept from a header (the web writer uses 1 MiB;
  /// this guards a hostile header from asking us to buffer gigabytes).
  static const int maxRecordSize = 64 * 1024 * 1024;

  static final AesGcm _aes = AesGcm.with256bits();

  /// Decode a `#k=` fragment value (URL-safe base64, no padding) to the raw
  /// 32-byte key, or null if it isn't one.
  static Uint8List? decodeKey(String s) {
    final b64 = s.replaceAll('-', '+').replaceAll('_', '/');
    final padded = b64.padRight(b64.length + (4 - b64.length % 4) % 4, '=');
    try {
      final raw = base64.decode(padded);
      return raw.length == 32 ? Uint8List.fromList(raw) : null;
    } on FormatException {
      return null;
    }
  }

  /// True when [file] starts with the BSE2 magic — i.e. it is an encrypted
  /// web-transfer container, not the plain payload.
  static Future<bool> sniff(File file) async {
    final raf = await file.open();
    try {
      final head = await raf.read(magic.length);
      if (head.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic[i]) return false;
      }
      return true;
    } finally {
      await raf.close();
    }
  }

  /// Stream-decrypt [input] (a BSE2 container) into [output]. Throws
  /// [Bse2Exception] on a bad key, tampered/reordered records, truncation, or
  /// an unsupported header. [onProgress] reports plaintext bytes produced.
  static Future<void> decryptFile({
    required File input,
    required File output,
    required Uint8List key,
    void Function(int plainBytes, int plainTotal)? onProgress,
  }) async {
    final secretKey = SecretKey(key);
    final raf = await input.open();
    final sink = await output.open(mode: FileMode.write);
    try {
      final header = await raf.read(headerSize);
      if (header.length != headerSize) {
        throw const Bse2Exception('truncated header');
      }
      for (var i = 0; i < magic.length; i++) {
        if (header[i] != magic[i]) {
          throw const Bse2Exception('not an encrypted file');
        }
      }
      if (header[4] != version) {
        throw const Bse2Exception('unsupported version');
      }
      final salt = header.sublist(8, 12);
      final view = ByteData.sublistView(header);
      final recordSize = view.getUint32(12);
      final plaintextSize = view.getUint64(16);
      if (recordSize < 1 || recordSize > maxRecordSize) {
        throw const Bse2Exception('invalid record size');
      }

      // max(1, ceil): a zero-byte file is one empty record (tag only).
      final records = plaintextSize == 0
          ? 1
          : (plaintextSize + recordSize - 1) ~/ recordSize;

      var produced = 0;
      for (var i = 0; i < records; i++) {
        final plainLen = plaintextSize == 0
            ? 0
            : (i == records - 1
                  ? plaintextSize - i * recordSize
                  : recordSize);
        final ct = await raf.read(plainLen + tagSize);
        if (ct.length != plainLen + tagSize) {
          throw const Bse2Exception('truncated stream');
        }
        final List<int> plain;
        try {
          plain = await _aes.decrypt(
            SecretBox(
              ct.sublist(0, plainLen),
              nonce: _nonceFor(salt, i),
              mac: Mac(ct.sublist(plainLen)),
            ),
            secretKey: secretKey,
            aad: _aadFor(i),
          );
        } on SecretBoxAuthenticationError {
          throw const Bse2Exception(
            'decryption failed — wrong key or corrupted file',
          );
        }
        await sink.writeFrom(plain);
        produced += plain.length;
        onProgress?.call(produced, plaintextSize);
      }

      // The container must end exactly after the last record.
      if ((await raf.read(1)).isNotEmpty) {
        throw const Bse2Exception('unexpected trailing data');
      }
      await sink.flush();
    } finally {
      await raf.close();
      await sink.close();
    }
  }

  /// iv = salt(4) ‖ u64BE(record index).
  static Uint8List _nonceFor(List<int> salt, int index) {
    final iv = Uint8List(12);
    iv.setRange(0, 4, salt);
    ByteData.sublistView(iv).setUint64(4, index);
    return iv;
  }

  /// aad = u32BE(record index).
  static Uint8List _aadFor(int index) {
    final aad = Uint8List(4);
    ByteData.sublistView(aad).setUint32(0, index);
    return aad;
  }
}
