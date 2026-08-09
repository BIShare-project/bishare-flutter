use aes_gcm::{
    aead::{Aead, KeyInit, OsRng},
    Aes256Gcm, Nonce,
};
use hkdf::Hkdf;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

use crate::constants::Crypto as CryptoConst;

/// Fixed DER SubjectPublicKeyInfo header for X25519 (RFC 8410) —
/// legacy Android clients send public keys as 44-byte X.509 SPKI (prefix + 32 raw bytes)
const X509_X25519_PREFIX: [u8; 12] = [0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00];

/// Normalize a public key to raw 32 bytes: accepts raw 32-byte keys
/// or legacy 44-byte X.509 SPKI keys (12-byte DER prefix + 32 raw bytes)
fn normalize_raw_key(bytes: &[u8]) -> Option<[u8; 32]> {
    let raw: &[u8] = match bytes.len() {
        32 => bytes,
        44 if bytes[..12] == X509_X25519_PREFIX => &bytes[12..],
        _ => return None,
    };
    let mut key = [0u8; 32];
    key.copy_from_slice(raw);
    Some(key)
}

/// BIShare encryption service — X25519 ECDH + HKDF-SHA256 + AES-256-GCM
pub struct Encryption {
    private_key: StaticSecret,
    public_key: PublicKey,
}

impl Encryption {
    /// Create with new random keypair
    pub fn new() -> Self {
        let private_key = StaticSecret::random_from_rng(OsRng);
        let public_key = PublicKey::from(&private_key);
        Self { private_key, public_key }
    }

    /// Create from existing private key bytes (32 bytes)
    pub fn from_private_key(bytes: &[u8; 32]) -> Self {
        let private_key = StaticSecret::from(*bytes);
        let public_key = PublicKey::from(&private_key);
        Self { private_key, public_key }
    }

    /// Get public key as base64
    pub fn public_key_base64(&self) -> String {
        base64::Engine::encode(&base64::engine::general_purpose::STANDARD, self.public_key.as_bytes())
    }

    /// Get private key bytes for persistence
    pub fn private_key_bytes(&self) -> [u8; 32] {
        self.private_key.to_bytes()
    }

    /// Compute key fingerprint: SHA256(publicKey)[0:8] as hex "AA BB CC DD..."
    pub fn fingerprint(&self) -> String {
        Self::compute_fingerprint(self.public_key.as_bytes())
    }

    /// Compute fingerprint from base64 public key (raw or legacy X.509 SPKI)
    /// Fingerprint is always over the raw 32 bytes
    pub fn peer_fingerprint(base64_key: &str) -> Option<String> {
        let bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, base64_key).ok()?;
        let raw = normalize_raw_key(&bytes)?;
        Some(Self::compute_fingerprint(&raw))
    }

    fn compute_fingerprint(key_bytes: &[u8]) -> String {
        let hash = Sha256::digest(key_bytes);
        hash.iter()
            .take(CryptoConst::FINGERPRINT_BYTES)
            .map(|b| format!("{:02X}", b))
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Derive shared encryption key from peer's base64 public key (raw or legacy X.509 SPKI)
    /// Returns 32-byte AES-256 key via HKDF-SHA256
    pub fn derive_shared_key(&self, peer_public_key_base64: &str) -> Option<[u8; 32]> {
        let peer_bytes = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, peer_public_key_base64).ok()?;
        let peer_key_bytes = normalize_raw_key(&peer_bytes)?;
        let peer_public = PublicKey::from(peer_key_bytes);

        let shared_secret = self.private_key.diffie_hellman(&peer_public);

        // Reject low-order/identity points (all-zero shared secret) — iOS CryptoKit
        // and Android JCA fail closed on these; without this check the derived key
        // would be publicly computable
        if !shared_secret.was_contributory() {
            return None;
        }

        // HKDF-SHA256
        let hkdf = Hkdf::<Sha256>::new(Some(CryptoConst::E2E_SALT), shared_secret.as_bytes());
        let mut key = [0u8; CryptoConst::AES_KEY_SIZE];
        hkdf.expand(CryptoConst::E2E_INFO, &mut key).ok()?;
        Some(key)
    }

    // ── AES-256-GCM (whole data) ──

    /// Encrypt data with AES-256-GCM. Returns: nonce(12) + ciphertext + tag(16)
    pub fn encrypt(data: &[u8], key: &[u8; 32]) -> Option<Vec<u8>> {
        let cipher = Aes256Gcm::new_from_slice(key).ok()?;
        let nonce_bytes = generate_random_bytes::<{ CryptoConst::GCM_NONCE_SIZE }>();
        let nonce = Nonce::from_slice(&nonce_bytes);
        let ciphertext = cipher.encrypt(nonce, data).ok()?;

        let mut result = Vec::with_capacity(CryptoConst::GCM_NONCE_SIZE + ciphertext.len());
        result.extend_from_slice(&nonce_bytes);
        result.extend_from_slice(&ciphertext);
        Some(result)
    }

    /// Decrypt data. Input: nonce(12) + ciphertext + tag(16)
    pub fn decrypt(data: &[u8], key: &[u8; 32]) -> Option<Vec<u8>> {
        if data.len() < CryptoConst::GCM_NONCE_SIZE + CryptoConst::GCM_TAG_BITS / 8 {
            return None;
        }

        let cipher = Aes256Gcm::new_from_slice(key).ok()?;
        let nonce = Nonce::from_slice(&data[..CryptoConst::GCM_NONCE_SIZE]);
        let ciphertext = &data[CryptoConst::GCM_NONCE_SIZE..];
        cipher.decrypt(nonce, ciphertext).ok()
    }

    // ── Streaming chunk encryption (v2.2) ──

    /// Generate 12 random bytes for base nonce
    pub fn generate_base_nonce() -> [u8; 12] {
        generate_random_bytes::<12>()
    }

    /// Encrypt a chunk with deterministic nonce derivation
    /// Nonce = baseNonce[0..4] + (baseNonce[4..12] XOR chunkIndex.to_be_bytes())
    pub fn encrypt_chunk(data: &[u8], key: &[u8; 32], chunk_index: u64, base_nonce: &[u8; 12]) -> Option<Vec<u8>> {
        let nonce_bytes = derive_chunk_nonce(base_nonce, chunk_index);
        let cipher = Aes256Gcm::new_from_slice(key).ok()?;
        let nonce = Nonce::from_slice(&nonce_bytes);
        let ciphertext = cipher.encrypt(nonce, data).ok()?;

        let mut result = Vec::with_capacity(CryptoConst::GCM_NONCE_SIZE + ciphertext.len());
        result.extend_from_slice(&nonce_bytes);
        result.extend_from_slice(&ciphertext);
        Some(result)
    }

    /// Decrypt a chunk with nonce verification
    pub fn decrypt_chunk(data: &[u8], key: &[u8; 32], chunk_index: u64, base_nonce: &[u8; 12]) -> Option<Vec<u8>> {
        if data.len() < CryptoConst::GCM_OVERHEAD_PER_CHUNK {
            return None;
        }

        let expected_nonce = derive_chunk_nonce(base_nonce, chunk_index);
        let actual_nonce = &data[..CryptoConst::GCM_NONCE_SIZE];

        // Verify nonce matches expected
        if actual_nonce != expected_nonce {
            return None;
        }

        let cipher = Aes256Gcm::new_from_slice(key).ok()?;
        let nonce = Nonce::from_slice(actual_nonce);
        let ciphertext = &data[CryptoConst::GCM_NONCE_SIZE..];
        cipher.decrypt(nonce, ciphertext).ok()
    }

    // ── SHA-256 ──

    /// Compute SHA-256 hash of data, return hex string
    pub fn sha256_hex(data: &[u8]) -> String {
        let hash = Sha256::digest(data);
        hex::encode(hash)
    }
}

impl Default for Encryption {
    fn default() -> Self {
        Self::new()
    }
}

// ── Content-key wrapping (v2.4 broadcast) ──

/// Envelope size for a wrapped content key: nonce(12) + ciphertext(32) + tag(16)
pub const WRAPPED_CONTENT_KEY_SIZE: usize =
    CryptoConst::GCM_NONCE_SIZE + CryptoConst::AES_KEY_SIZE + CryptoConst::GCM_TAG_BITS / 8; // 60

/// Wrap a 32-byte content key under a KEK (AES-256-GCM).
/// KEK = `derive_shared_key(peer_pub)`. Returns 60-byte envelope: nonce(12) + ct(32) + tag(16)
pub fn wrap_content_key(ck: &[u8; 32], kek: &[u8; 32]) -> Option<Vec<u8>> {
    Encryption::encrypt(ck, kek)
}

/// Unwrap a 60-byte envelope back into the 32-byte content key
pub fn unwrap_content_key(envelope: &[u8], kek: &[u8; 32]) -> Option<[u8; 32]> {
    if envelope.len() != WRAPPED_CONTENT_KEY_SIZE {
        return None;
    }
    let plain = Encryption::decrypt(envelope, kek)?;
    let mut ck = [0u8; 32];
    ck.copy_from_slice(plain.get(..32)?);
    Some(ck)
}

// ── Content-addressed E2E sync blobs (Tahap 4 §7.1) ──

/// Deterministic 12-byte AES-GCM base nonce for a content-addressed sync blob:
/// `HKDF-SHA256(salt = "bishare-sync-blob-nonce", ikm = pair_key,
/// info = plaintext_sha256_hex)` → the first 12 bytes.
///
/// Deterministic in `(pair_key, content)` ON PURPOSE: re-encrypting the same
/// file yields byte-identical ciphertext, so its ciphertext hash is stable and
/// `POST /files/check-exists` dedup + idempotent upload-retry survive E2E (the
/// property that made Q2=yes viable without a backend change). Distinct content
/// ⇒ distinct `plaintext_sha256_hex` ⇒ distinct nonce (SHA-256 collision
/// resistance), so a fixed `pair_key` never reuses a `(key, nonce)` pair across
/// different blobs — the one invariant AES-GCM must never violate. Combine with
/// `encrypt_chunk(_, pair_key, chunk_index, base_nonce)` for multi-chunk blobs.
pub fn derive_blob_base_nonce(pair_key: &[u8; 32], plaintext_sha256_hex: &str) -> [u8; 12] {
    let hk = Hkdf::<Sha256>::new(Some(b"bishare-sync-blob-nonce"), pair_key);
    let mut nonce = [0u8; 12];
    hk.expand(plaintext_sha256_hex.as_bytes(), &mut nonce)
        .expect("HKDF-SHA256 expand of 12 bytes is always within output length");
    nonce
}

/// Derive per-chunk nonce: baseNonce XOR pad(chunkIndex, 12)
/// XOR chunkIndex (8 bytes big-endian) into bytes [4..12] of base nonce
fn derive_chunk_nonce(base_nonce: &[u8; 12], chunk_index: u64) -> [u8; 12] {
    let mut nonce = *base_nonce;
    let index_bytes = chunk_index.to_be_bytes();
    for i in 0..8 {
        nonce[4 + i] ^= index_bytes[i];
    }
    nonce
}

fn generate_random_bytes<const N: usize>() -> [u8; N] {
    let mut bytes = [0u8; N];
    rand::RngCore::fill_bytes(&mut rand::rngs::OsRng, &mut bytes);
    bytes
}

// Need hex encoding for sha256
mod hex {
    pub fn encode(data: impl AsRef<[u8]>) -> String {
        data.as_ref().iter().map(|b| format!("{:02x}", b)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::{assert_eq, assert_ne};

    // ── Cross-platform test vectors (shared with iOS/Android suites — must stay exact) ──

    const VECTOR_PLAINTEXT: &[u8] = b"BIShare cross-platform test vector";
    const CHUNK0_HEX: &str = "000102030405060708090a0b054b8573a497a73bee33f8f8c2c40801e2a2e15b82167f085d1491a56b0c63c66e623f9e794f97a98205cb0b27157af11d24";
    const CHUNK1_HEX: &str = "000102030405060708090a0ae4919a286eaa2a8ab4336e2bb89bf638a0dbbe6526429e3a4a4f0bad6b9648c23ecf16cfba5fdc41ea16333b7dbc9d97f427";
    const PUB_A_B64: &str = "e06Qm75//kTEZaIgA31gjuNYl9Me+XLwf3SJLLD3PxM=";
    const PUB_B_B64: &str = "D6poTtKIZ7l/Smot7l34zpdOdrcBjj8iocTPJnhXDyA=";
    const PUB_A_X509_B64: &str = "MCowBQYDK2VuAyEAe06Qm75//kTEZaIgA31gjuNYl9Me+XLwf3SJLLD3PxM=";
    const SHARED_KEY_HEX: &str = "9ffee322ad64e3bf95f3dc3e6c979113af57b356ed7b7fb9cb6bfe4a55eba48c";
    const FINGERPRINT_A: &str = "D1 9B F3 F0 82 78 2C 87";

    /// Vector key: 32 ascending bytes 00..1f
    fn vector_key() -> [u8; 32] {
        core::array::from_fn(|i| i as u8)
    }

    /// Vector base nonce: 12 ascending bytes 00..0b
    fn vector_base_nonce() -> [u8; 12] {
        core::array::from_fn(|i| i as u8)
    }

    fn hex_decode(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn test_encrypt_chunk_vectors() {
        let key = vector_key();
        let nonce = vector_base_nonce();
        let c0 = Encryption::encrypt_chunk(VECTOR_PLAINTEXT, &key, 0, &nonce).unwrap();
        assert_eq!(hex::encode(&c0), CHUNK0_HEX);
        let c1 = Encryption::encrypt_chunk(VECTOR_PLAINTEXT, &key, 1, &nonce).unwrap();
        assert_eq!(hex::encode(&c1), CHUNK1_HEX);
    }

    #[test]
    fn test_decrypt_chunk_vector_roundtrip() {
        let key = vector_key();
        let nonce = vector_base_nonce();
        let plain0 = Encryption::decrypt_chunk(&hex_decode(CHUNK0_HEX), &key, 0, &nonce).unwrap();
        assert_eq!(plain0, VECTOR_PLAINTEXT);
        let plain1 = Encryption::decrypt_chunk(&hex_decode(CHUNK1_HEX), &key, 1, &nonce).unwrap();
        assert_eq!(plain1, VECTOR_PLAINTEXT);
    }

    #[test]
    fn test_fixed_keypair_vectors() {
        let a = Encryption::from_private_key(&[0x11; 32]);
        let b = Encryption::from_private_key(&[0x22; 32]);
        assert_eq!(a.public_key_base64(), PUB_A_B64);
        assert_eq!(b.public_key_base64(), PUB_B_B64);

        let key_ab = a.derive_shared_key(&b.public_key_base64()).unwrap();
        let key_ba = b.derive_shared_key(&a.public_key_base64()).unwrap();
        assert_eq!(key_ab, key_ba);
        assert_eq!(hex::encode(key_ab), SHARED_KEY_HEX);
        assert_eq!(a.fingerprint(), FINGERPRINT_A);
    }

    #[test]
    fn test_x509_public_key_accepted() {
        // Legacy Android clients send 44-byte X.509 SPKI keys — must derive the same shared key
        let b = Encryption::from_private_key(&[0x22; 32]);
        let key = b.derive_shared_key(PUB_A_X509_B64).unwrap();
        assert_eq!(hex::encode(key), SHARED_KEY_HEX);

        // Fingerprint is always over the raw 32 bytes, whichever form the key arrives in
        let fp_x509 = Encryption::peer_fingerprint(PUB_A_X509_B64).unwrap();
        let fp_raw = Encryption::peer_fingerprint(PUB_A_B64).unwrap();
        assert_eq!(fp_x509, fp_raw);
        assert_eq!(fp_raw, FINGERPRINT_A);
    }

    #[test]
    fn test_low_order_peer_key_rejected() {
        // All-zero / low-order X25519 points yield a non-contributory shared secret;
        // the derived key would be publicly computable. iOS and Android fail closed —
        // Rust must too. (Cross-platform negative vector.)
        let a = Encryption::from_private_key(&[0x11; 32]);
        let zero_key = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, [0u8; 32]);
        assert_eq!(a.derive_shared_key(&zero_key), None);

        // Order-8 low-order point (RFC 7748 test constant)
        let low_order: [u8; 32] = [
            0xe0, 0xeb, 0x7a, 0x7c, 0x3b, 0x41, 0xb8, 0xae, 0x16, 0x56, 0xe3, 0xfa, 0xf1, 0x9f,
            0xc4, 0x6a, 0xda, 0x09, 0x8d, 0xeb, 0x9c, 0x32, 0xb1, 0xfd, 0x86, 0x62, 0x05, 0x16,
            0x5f, 0x49, 0xb8, 0x00,
        ];
        let low_b64 = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, low_order);
        assert_eq!(a.derive_shared_key(&low_b64), None);
    }

    #[test]
    fn test_normalize_raw_key() {
        let raw = [0xABu8; 32];
        assert_eq!(normalize_raw_key(&raw), Some(raw));

        let mut x509 = X509_X25519_PREFIX.to_vec();
        x509.extend_from_slice(&raw);
        assert_eq!(normalize_raw_key(&x509), Some(raw));

        // Wrong lengths / wrong prefix rejected
        assert_eq!(normalize_raw_key(&[0u8; 31]), None);
        assert_eq!(normalize_raw_key(&[0u8; 44]), None);
    }

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let key = vector_key();
        let data = b"hello whole-data encryption";
        let encrypted = Encryption::encrypt(data, &key).unwrap();
        let decrypted = Encryption::decrypt(&encrypted, &key).unwrap();
        assert_eq!(decrypted, data.to_vec());
    }

    #[test]
    fn test_decrypt_wrong_key_fails() {
        let key = vector_key();
        let encrypted = Encryption::encrypt(b"secret", &key).unwrap();
        let wrong_key = [0xFFu8; 32];
        assert!(Encryption::decrypt(&encrypted, &wrong_key).is_none());
    }

    #[test]
    fn test_decrypt_chunk_wrong_index_fails() {
        let key = vector_key();
        let nonce = vector_base_nonce();
        let chunk = Encryption::encrypt_chunk(VECTOR_PLAINTEXT, &key, 3, &nonce).unwrap();
        assert!(Encryption::decrypt_chunk(&chunk, &key, 4, &nonce).is_none());
    }

    #[test]
    fn test_generate_base_nonce() {
        let n1 = Encryption::generate_base_nonce();
        let n2 = Encryption::generate_base_nonce();
        assert_eq!(n1.len(), 12);
        assert_ne!(n1, n2);
    }

    // ── Content-key wrapping vectors (v2.4 broadcast) ──

    /// Envelope of WRAPPED_CK under kek=vector_key() with nonce=vector_base_nonce():
    /// nonce(12) + ct(32) + tag(16) = 60 bytes
    const WRAPPED_CK_HEX: &str = "000102030405060708090a0b6723f438e1c0e43ca568bda09dc45642b3e7b507c44e694b005edfbe21543e8d74943e2a269bf4fe0b89d0e48c7cdd01";

    /// Vector content key: 32 ascending bytes 20..3f
    fn vector_content_key() -> [u8; 32] {
        core::array::from_fn(|i| 0x20 + i as u8)
    }

    #[test]
    fn test_unwrap_content_key_vector() {
        // Fixed regression vector — envelope built with the vector base nonce must
        // always unwrap to the same content key (byte-exact across platforms)
        let envelope = hex_decode(WRAPPED_CK_HEX);
        assert_eq!(envelope.len(), WRAPPED_CONTENT_KEY_SIZE);
        let ck = unwrap_content_key(&envelope, &vector_key()).unwrap();
        assert_eq!(ck, vector_content_key());
    }

    #[test]
    fn test_wrap_content_key_roundtrip() {
        let ck = vector_content_key();
        let kek = vector_key();
        let envelope = wrap_content_key(&ck, &kek).unwrap();
        assert_eq!(envelope.len(), 60);
        assert_eq!(unwrap_content_key(&envelope, &kek), Some(ck));
        // Random nonce → two wraps of the same key differ
        let envelope2 = wrap_content_key(&ck, &kek).unwrap();
        assert_ne!(envelope, envelope2);
        assert_eq!(unwrap_content_key(&envelope2, &kek), Some(ck));
    }

    #[test]
    fn test_unwrap_content_key_wrong_kek_fails() {
        let envelope = wrap_content_key(&vector_content_key(), &vector_key()).unwrap();
        let wrong_kek = [0xFFu8; 32];
        assert_eq!(unwrap_content_key(&envelope, &wrong_kek), None);
    }

    #[test]
    fn test_unwrap_content_key_wrong_length_fails() {
        let kek = vector_key();
        let envelope = wrap_content_key(&vector_content_key(), &kek).unwrap();
        // Anything other than the exact 60-byte envelope is rejected
        assert_eq!(unwrap_content_key(&envelope[..59], &kek), None);
        assert_eq!(unwrap_content_key(&[0u8; 61], &kek), None);
        assert_eq!(unwrap_content_key(&[], &kek), None);
    }

    #[test]
    fn test_decrypt_too_short_returns_none() {
        let key = vector_key();
        assert!(Encryption::decrypt(&[0u8; 10], &key).is_none());
        assert!(Encryption::decrypt_chunk(&[0u8; 27], &key, 0, &vector_base_nonce()).is_none());
    }

    // ── Tahap 4 §7.1 — E2E content-addressed sync blobs (M0 validation) ──
    // Proves the cloud-path crypto composes ENTIRELY from shipped primitives
    // (wrap/unwrap_content_key v2.4 + encrypt_chunk v2.2) plus one deterministic
    // nonce, so Q2=yes needs no new audited crypto and no backend change.

    /// Pairing bootstrap: device A mints the pair key and wraps it to device B's
    /// identity pubkey; B recovers it with its own derived KEK. The pair key
    /// never touches the server — exactly the §7.1 LAN/QR key exchange.
    #[test]
    fn m0_sync_pairkey_wrap_bootstrap_over_x25519() {
        let a = Encryption::from_private_key(&[0x11; 32]);
        let b = Encryption::from_private_key(&[0x22; 32]);
        let pair_key: [u8; 32] = core::array::from_fn(|i| (i as u8) ^ 0xA5);

        let kek_a = a.derive_shared_key(&b.public_key_base64()).unwrap();
        let envelope = wrap_content_key(&pair_key, &kek_a).unwrap();
        assert_eq!(envelope.len(), WRAPPED_CONTENT_KEY_SIZE);

        // B derives the SAME shared key from A's pubkey and recovers the pair key.
        let kek_b = b.derive_shared_key(&a.public_key_base64()).unwrap();
        assert_eq!(unwrap_content_key(&envelope, &kek_b).unwrap(), pair_key);

        // A third device cannot unwrap what was sealed to B.
        let stranger = Encryption::from_private_key(&[0x33; 32]);
        let kek_s = stranger.derive_shared_key(&a.public_key_base64()).unwrap();
        assert_eq!(unwrap_content_key(&envelope, &kek_s), None);
    }

    /// Deterministic nonce ⇒ identical ciphertext for identical content ⇒
    /// check-exists dedup/idempotent-retry survive E2E; and it round-trips.
    #[test]
    fn m0_sync_blob_deterministic_idempotent_and_roundtrips() {
        let pair_key = [0x7cu8; 32];
        let plaintext = b"the quick brown fox jumps over the lazy dog, and then again";
        let sha = Encryption::sha256_hex(plaintext);

        let n1 = derive_blob_base_nonce(&pair_key, &sha);
        let n2 = derive_blob_base_nonce(&pair_key, &sha);
        assert_eq!(n1, n2, "nonce is deterministic in (pairKey, content)");

        let c1 = Encryption::encrypt_chunk(plaintext, &pair_key, 0, &n1).unwrap();
        let c2 = Encryption::encrypt_chunk(plaintext, &pair_key, 0, &n2).unwrap();
        assert_eq!(c1, c2, "same content re-encrypts byte-identically");
        // ⇒ the content-addressed blob name (ciphertext hash) is stable.
        assert_eq!(Encryption::sha256_hex(&c1), Encryption::sha256_hex(&c2));

        let back = Encryption::decrypt_chunk(&c1, &pair_key, 0, &n1).unwrap();
        assert_eq!(back, plaintext, "round-trips to the original bytes");
    }

    /// Distinct content (or distinct pair) ⇒ distinct nonce: no (key, nonce)
    /// reuse across blobs, the one invariant AES-GCM must never break.
    #[test]
    fn m0_sync_blob_distinct_content_distinct_nonce() {
        let pair_key = [0x7cu8; 32];
        let sha_a = Encryption::sha256_hex(b"content A");
        let sha_b = Encryption::sha256_hex(b"content B");
        assert_ne!(
            derive_blob_base_nonce(&pair_key, &sha_a),
            derive_blob_base_nonce(&pair_key, &sha_b)
        );
        // Cross-pair isolation: same content under a different pair key diverges.
        assert_ne!(
            derive_blob_base_nonce(&pair_key, &sha_a),
            derive_blob_base_nonce(&[0x01u8; 32], &sha_a)
        );
    }

    /// A wrong pair key cannot open a blob even with the correct nonce — GCM
    /// authentication fails closed (no silent garbage plaintext).
    #[test]
    fn m0_sync_blob_wrong_key_fails_closed() {
        let pair_key = [0x7cu8; 32];
        let wrong = [0x7du8; 32];
        let pt = b"secret sync payload";
        let nonce = derive_blob_base_nonce(&pair_key, &Encryption::sha256_hex(pt));
        let ct = Encryption::encrypt_chunk(pt, &pair_key, 0, &nonce).unwrap();
        assert!(Encryption::decrypt_chunk(&ct, &wrong, 0, &nonce).is_none());
    }
}
