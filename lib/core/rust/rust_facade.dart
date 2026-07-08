import 'dart:typed_data';

import '../../src/rust/api/crypto.dart' as rc;
import '../../src/rust/api/utils.dart' as ru;
import '../../src/rust/frb_generated.dart';

/// Ergonomic Dart-side wrapper over the generated flutter_rust_bridge bindings.
/// Everything here executes the **shared `bishare-protocol` Rust code**, so
/// crypto/naming is byte-identical to iOS/Android. [ensureInitialized] must run
/// (via `bootstrap()`) before any call.
class Rust {
  Rust._();

  static bool _ready = false;

  /// Loads the native library exactly once.
  static Future<void> ensureInitialized() async {
    if (_ready) return;
    await RustLib.init();
    _ready = true;
  }

  // ---- utils ----
  static String sanitizeFilename(String name) =>
      ru.sanitizeFilename(name: name);
  static String categoryName(String mimeType) =>
      ru.categoryName(mimeType: mimeType);
  static String roomCode() => ru.roomCode();
  static String transferCode() => ru.transferCode();
  static String smartName(String originalName, String senderAlias) =>
      ru.smartName(originalName: originalName, senderAlias: senderAlias);

  // ---- crypto (shared engine; the pure-Dart E2ECrypto stays as the fallback) ----
  static String sha256Hex(List<int> data) => rc.sha256Hex(data: data);
  static String? peerFingerprint(String base64Key) =>
      rc.peerFingerprint(base64Key: base64Key);
  static List<int> generateBaseNonce() => rc.generateBaseNonce();
  static rc.EncryptionEngine newEngine() => rc.EncryptionEngine.generate();
  static rc.EncryptionEngine? engineFromSeed(List<int> seed) =>
      rc.EncryptionEngine.fromSeed(seed: seed);

  /// Encrypt one transfer chunk → `nonce(12) | ciphertext | tag(16)`.
  ///
  /// **Async**: the underlying `encrypt_chunk` is no longer `frb(sync)`, so FRB
  /// runs AES-256-GCM on its Rust worker-thread pool — the Dart event loop stays
  /// free to drive the socket in parallel (network↔crypto overlap → ~45 MB/s).
  static Future<Uint8List?> encryptChunk(
    Uint8List data,
    List<int> key,
    int chunkIndex,
    List<int> baseNonce,
  ) => rc.encryptChunk(
    data: data,
    key: key,
    chunkIndex: BigInt.from(chunkIndex),
    baseNonce: baseNonce,
  );

  /// Decrypt one transfer chunk from combined form. **Async** — see [encryptChunk];
  /// decrypt overlaps socket recv on the receiver.
  static Future<Uint8List?> decryptChunk(
    Uint8List data,
    List<int> key,
    int chunkIndex,
    List<int> baseNonce,
  ) => rc.decryptChunk(
    data: data,
    key: key,
    chunkIndex: BigInt.from(chunkIndex),
    baseNonce: baseNonce,
  );
}
