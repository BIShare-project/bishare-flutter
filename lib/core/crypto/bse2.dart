import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../rust/rust_facade.dart';

/// The end-to-end-encrypted container for cloud transfer links — the same
/// "BSE2" format the web client writes and reads.
///
/// The cryptography lives in ONE place: `bishare-protocol/src/bse2.rs` (the
/// canonical spec, pinned to WebCrypto golden vectors). This class is a thin
/// Dart face over that Rust code via flutter_rust_bridge, so the app seals
/// its Remote Share uploads and opens web uploads with byte-identical logic —
/// and with hardware AES where the platform has it, off the Dart event loop.
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
/// The 32-byte key rides in the share link's URL fragment (`#k=<base64url>`),
/// which browsers never send to the server — so the relay only ever stores
/// ciphertext, and whoever holds the link (not the code alone) can open it.
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
  static const int keySize = 32;

  /// Plaintext bytes per record — what every production writer uses.
  static const int recordSize = 1024 * 1024;

  /// Fresh random 32-byte key for one transfer (Rust CSPRNG).
  static Uint8List generateKey() => Rust.bse2GenerateKey();

  /// URL-safe base64, no padding — the text after `#k=` in the share link.
  static String encodeKey(List<int> raw) =>
      base64Url.encode(raw).replaceAll('=', '');

  /// Decode a `#k=` fragment value to the raw 32-byte key, or null if it
  /// isn't one. Tolerates padding, like the web and Rust readers.
  static Uint8List? decodeKey(String s) {
    final b64 = s.replaceAll('-', '+').replaceAll('_', '/');
    final padded = b64.padRight(b64.length + (4 - b64.length % 4) % 4, '=');
    try {
      final raw = base64.decode(padded);
      return raw.length == keySize ? Uint8List.fromList(raw) : null;
    } on FormatException {
      return null;
    }
  }

  /// Exact container length for a plaintext of [plaintextSize] bytes. The
  /// uploader must reserve THIS, not the plaintext size — the relay only ever
  /// sees ciphertext. Mirrors `bse2::ciphertext_size` (asserted equal in
  /// tests); pure Dart so size gates work before the bridge is touched.
  static int ciphertextSize(int plaintextSize) {
    final records = plaintextSize == 0
        ? 1
        : (plaintextSize + recordSize - 1) ~/ recordSize;
    return headerSize + plaintextSize + records * tagSize;
  }

  /// True when [file] starts with the BSE2 magic — i.e. it is an encrypted
  /// container, not the plain payload.
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

  /// Seal [input] into a new container at [output] under [key] (a fresh
  /// random salt is chosen in Rust). [onProgress] reports plaintext bytes
  /// done / total. Throws [Bse2Exception] on any failure; the partial output
  /// is removed by Rust, so a caller can never upload a stub.
  static Future<void> encryptFile({
    required File input,
    required File output,
    required Uint8List key,
    void Function(int plainBytes, int plainTotal)? onProgress,
  }) async {
    if (key.length != keySize) {
      throw const Bse2Exception('key must be 32 bytes');
    }
    try {
      await for (final p in Rust.bse2EncryptFile(
        inputPath: input.path,
        outputPath: output.path,
        key: key,
      )) {
        onProgress?.call(p.done.toInt(), p.total.toInt());
      }
    } on Object catch (e) {
      throw Bse2Exception(_message(e));
    }
  }

  /// Open the container at [input] into the plaintext file at [output].
  /// Throws [Bse2Exception] on a bad key, tampered/reordered records,
  /// truncation, trailing bytes or an unsupported header — never partial
  /// output reported as success. [onProgress] reports plaintext bytes
  /// produced / total.
  static Future<void> decryptFile({
    required File input,
    required File output,
    required Uint8List key,
    void Function(int plainBytes, int plainTotal)? onProgress,
  }) async {
    if (key.length != keySize) {
      throw const Bse2Exception('key must be 32 bytes');
    }
    try {
      await for (final p in Rust.bse2DecryptFile(
        inputPath: input.path,
        outputPath: output.path,
        key: key,
      )) {
        onProgress?.call(p.done.toInt(), p.total.toInt());
      }
    } on Object catch (e) {
      throw Bse2Exception(_message(e));
    }
  }

  /// Rust delivers failures into the progress stream as a plain message (the
  /// FRB sink-fn rule); unwrap whatever wrapper the bridge put around it.
  static String _message(Object e) {
    if (e is Bse2Exception) return e.message;
    if (e is AnyhowException) return e.message;
    return e.toString();
  }
}
