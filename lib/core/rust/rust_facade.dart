import 'dart:typed_data';

import '../../src/rust/api/bse2.dart' as rb;
import '../../src/rust/api/crypto.dart' as rc;
import '../../src/rust/api/utils.dart' as ru;
import '../../src/rust/api/vault.dart' as rv;
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

  /// Build the shared engine from a seed, or null if the seed is invalid OR the
  /// Rust bridge isn't loaded. Never throws — [DeviceIdentity.load] relies on
  /// this so a missing bridge degrades transfers instead of blanking launch.
  static rc.EncryptionEngine? engineFromSeed(List<int> seed) {
    try {
      return rc.EncryptionEngine.fromSeed(seed: seed);
    } on Object {
      return null;
    }
  }

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

  // ---- BSE2: the end-to-end-encrypted cloud-link container (shared spec) ----
  static Uint8List bse2GenerateKey() => rb.bse2GenerateKey();
  static int bse2CiphertextSize(int plaintextSize) =>
      rb.bse2CiphertextSize(plaintextSize: BigInt.from(plaintextSize)).toInt();

  /// Seal a file into a fresh container. Progress streams from a Rust thread;
  /// a failure arrives as a stream error (see [Bse2.encryptFile]).
  static Stream<rb.Bse2Progress> bse2EncryptFile({
    required String inputPath,
    required String outputPath,
    required List<int> key,
  }) => rb.bse2EncryptFile(
    inputPath: inputPath,
    outputPath: outputPath,
    key: key,
  );

  /// Open a container into a plaintext file — same contract as
  /// [bse2EncryptFile].
  static Stream<rb.Bse2Progress> bse2DecryptFile({
    required String inputPath,
    required String outputPath,
    required List<int> key,
  }) => rb.bse2DecryptFile(
    inputPath: inputPath,
    outputPath: outputPath,
    key: key,
  );

  // ---- Vault (BIShare Drive): keys, envelopes and signatures (VAULT-SPEC.md) ----
  static Uint8List vaultGenerateKey() => rv.vaultGenerateKey();
  static Uint8List vaultGenerateFileKey() => rv.vaultGenerateFileKey();
  static String vaultGenerateObjectId() => rv.vaultGenerateObjectId();
  static bool vaultIsVaultId(String id) => rv.vaultIsVaultId(id: id);
  static bool vaultIsObjectId(String id) => rv.vaultIsObjectId(id: id);
  static String vaultKeyCheck(List<int> vaultKey) =>
      rv.vaultKeyCheck(vaultKey: vaultKey);
  static Uint8List vaultMetaKey(List<int> vaultKey) =>
      rv.vaultMetaKey(vaultKey: vaultKey);
  static Uint8List vaultThumbKey(List<int> fileKey) =>
      rv.vaultThumbKey(fileKey: fileKey);
  static Uint8List vaultDedupeKey(List<int> vaultKey) =>
      rv.vaultDedupeKey(vaultKey: vaultKey);
  static String vaultDedupeTag({
    required List<int> dedupeKey,
    required List<int> plaintextHash,
  }) => rv.vaultDedupeTag(dedupeKey: dedupeKey, plaintextHash: plaintextHash);
  static Uint8List vaultDeflateRaw(List<int> data) =>
      rv.vaultDeflateRaw(data: data);
  static Uint8List vaultInflateRaw(List<int> data, int expectedLen) =>
      rv.vaultInflateRaw(data: data, expectedLen: BigInt.from(expectedLen));
  static String vaultPhraseFromKey(List<int> vaultKey) =>
      rv.vaultPhraseFromKey(vaultKey: vaultKey);
  static Uint8List vaultKeyFromPhrase(String phrase) =>
      rv.vaultKeyFromPhrase(phrase: phrase);
  static Uint8List vaultSealKeyCopy({
    required List<int> serverHalf,
    required String vaultId,
    required List<int> vaultKey,
  }) => rv.vaultSealKeyCopy(
    serverHalf: serverHalf,
    vaultId: vaultId,
    vaultKey: vaultKey,
  );
  static Uint8List vaultOpenKeyCopy({
    required List<int> serverHalf,
    required String vaultId,
    required List<int> keyCopy,
  }) => rv.vaultOpenKeyCopy(
    serverHalf: serverHalf,
    vaultId: vaultId,
    keyCopy: keyCopy,
  );
  static String vaultSealMeta({
    required List<int> metaKey,
    required String vaultId,
    required String objectId,
    required rv.VaultMeta meta,
  }) => rv.vaultSealMeta(
    metaKey: metaKey,
    vaultId: vaultId,
    objectId: objectId,
    meta: meta,
  );
  static rv.VaultMeta vaultOpenMeta({
    required List<int> metaKey,
    required String vaultId,
    required String objectId,
    required String encMeta,
  }) => rv.vaultOpenMeta(
    metaKey: metaKey,
    vaultId: vaultId,
    objectId: objectId,
    encMeta: encMeta,
  );
  static String vaultSealDeviceName({
    required List<int> metaKey,
    required String vaultId,
    required String deviceId,
    required String name,
  }) => rv.vaultSealDeviceName(
    metaKey: metaKey,
    vaultId: vaultId,
    deviceId: deviceId,
    name: name,
  );
  static String vaultOpenDeviceName({
    required List<int> metaKey,
    required String vaultId,
    required String deviceId,
    required String encName,
  }) => rv.vaultOpenDeviceName(
    metaKey: metaKey,
    vaultId: vaultId,
    deviceId: deviceId,
    encName: encName,
  );
  static Uint8List vaultSealThumbnail({
    required List<int> fileKey,
    required String vaultId,
    required String objectId,
    required List<int> jpeg,
  }) => rv.vaultSealThumbnail(
    fileKey: fileKey,
    vaultId: vaultId,
    objectId: objectId,
    jpeg: jpeg,
  );
  static Uint8List vaultOpenThumbnail({
    required List<int> fileKey,
    required String vaultId,
    required String objectId,
    required List<int> sealed,
  }) => rv.vaultOpenThumbnail(
    fileKey: fileKey,
    vaultId: vaultId,
    objectId: objectId,
    sealed: sealed,
  );
  static Uint8List vaultGenerateLinkKey() => rv.vaultGenerateLinkKey();
  static String vaultSealLink({
    required List<int> linkKey,
    required String linkId,
    required String kind,
    required String name,
    required String vaultId,
    required List<rv.VaultLinkFile> files,
  }) => rv.vaultSealLink(
    linkKey: linkKey,
    linkId: linkId,
    kind: kind,
    name: name,
    vaultId: vaultId,
    files: files,
  );
  static String vaultOpenLinkJson({
    required List<int> linkKey,
    required String linkId,
    required String sealed,
  }) => rv.vaultOpenLinkJson(linkKey: linkKey, linkId: linkId, sealed: sealed);
  static String vaultSealLinkKey({
    required List<int> metaKey,
    required String vaultId,
    required String linkId,
    required List<int> linkKey,
  }) => rv.vaultSealLinkKey(
    metaKey: metaKey,
    vaultId: vaultId,
    linkId: linkId,
    linkKey: linkKey,
  );
  static Uint8List vaultOpenLinkKey({
    required List<int> metaKey,
    required String vaultId,
    required String linkId,
    required String sealed,
  }) => rv.vaultOpenLinkKey(
    metaKey: metaKey,
    vaultId: vaultId,
    linkId: linkId,
    sealed: sealed,
  );
  static rv.VaultGrantKey vaultGrantKeyGenerate() => rv.vaultGrantKeyGenerate();
  static Uint8List vaultGrant({
    required List<int> vaultKey,
    required String vaultId,
    required List<int> mineSecret,
    required List<int> newPub,
  }) => rv.vaultGrant(
    vaultKey: vaultKey,
    vaultId: vaultId,
    mineSecret: mineSecret,
    newPub: newPub,
  );
  static Uint8List vaultAcceptGrant({
    required String vaultId,
    required List<int> mineSecret,
    required List<int> granterPub,
    required List<int> boxed,
    required String expectedKeyCheck,
  }) => rv.vaultAcceptGrant(
    vaultId: vaultId,
    mineSecret: mineSecret,
    granterPub: granterPub,
    boxed: boxed,
    expectedKeyCheck: expectedKeyCheck,
  );
  static Uint8List vaultDeviceKeyGenerate() => rv.vaultDeviceKeyGenerate();
  static Uint8List vaultDevicePublicKey(List<int> seed) =>
      rv.vaultDevicePublicKey(seed: seed);
  static String vaultDeviceId(List<int> publicKey) =>
      rv.vaultDeviceId(publicKey: publicKey);
  static String vaultSigninNonce(List<int> publicKey) =>
      rv.vaultSigninNonce(publicKey: publicKey);
  static String vaultRequestMessage({
    required String method,
    required String pathAndQuery,
    required int ts,
    required List<int> body,
  }) => rv.vaultRequestMessage(
    method: method,
    pathAndQuery: pathAndQuery,
    ts: ts,
    body: body,
  );
  static String vaultSignRequest({
    required List<int> seed,
    required String method,
    required String pathAndQuery,
    required int ts,
    required List<int> body,
  }) => rv.vaultSignRequest(
    seed: seed,
    method: method,
    pathAndQuery: pathAndQuery,
    ts: ts,
    body: body,
  );

  /// The `Authorization` header of this device while it waits in a pairing
  /// slot (Windows and Linux, approved by a phone), before it has a vault.
  static String vaultPairAuthorization({
    required List<int> seed,
    required String slot,
    required String method,
    required String pathAndQuery,
    required int ts,
    required List<int> body,
  }) => rv.vaultPairAuthorization(
    seed: seed,
    slot: slot,
    method: method,
    pathAndQuery: pathAndQuery,
    ts: ts,
    body: body,
  );
  static String vaultAuthorization({
    required List<int> seed,
    required String vaultId,
    required String method,
    required String pathAndQuery,
    required int ts,
    required List<int> body,
  }) => rv.vaultAuthorization(
    seed: seed,
    vaultId: vaultId,
    method: method,
    pathAndQuery: pathAndQuery,
    ts: ts,
    body: body,
  );

  /// Throws with the reason when the signature does not verify.
  static void vaultVerifyRequest({
    required List<int> publicKey,
    required String method,
    required String pathAndQuery,
    required int ts,
    required List<int> body,
    required String signature,
  }) => rv.vaultVerifyRequest(
    publicKey: publicKey,
    method: method,
    pathAndQuery: pathAndQuery,
    ts: ts,
    body: body,
    signature: signature,
  );
}
