//! E2E crypto, re-using `bishare_protocol::crypto::Encryption` verbatim so the
//! wire format is identical to iOS/Android. Exposed to Dart via flutter_rust_bridge.

use bishare_protocol::crypto::Encryption;

/// An X25519 identity + AES-256-GCM engine. FRB exposes this as an opaque handle.
pub struct EncryptionEngine {
    inner: Encryption,
}

impl EncryptionEngine {
    /// Generate a fresh key pair.
    #[flutter_rust_bridge::frb(sync)]
    pub fn generate() -> EncryptionEngine {
        EncryptionEngine {
            inner: Encryption::new(),
        }
    }

    /// Restore from a stored 32-byte private seed.
    #[flutter_rust_bridge::frb(sync)]
    pub fn from_seed(seed: Vec<u8>) -> Option<EncryptionEngine> {
        let arr: [u8; 32] = seed.try_into().ok()?;
        Some(EncryptionEngine {
            inner: Encryption::from_private_key(&arr),
        })
    }

    /// Base64 of the raw 32-byte public key (goes into `DeviceInfo.publicKey`).
    #[flutter_rust_bridge::frb(sync)]
    pub fn public_key_base64(&self) -> String {
        self.inner.public_key_base64()
    }

    /// Raw 32-byte private seed for persistence.
    #[flutter_rust_bridge::frb(sync)]
    pub fn private_seed(&self) -> Vec<u8> {
        self.inner.private_key_bytes().to_vec()
    }

    /// Visual fingerprint of our own public key.
    #[flutter_rust_bridge::frb(sync)]
    pub fn fingerprint(&self) -> String {
        self.inner.fingerprint()
    }

    /// Derive the shared AES-256 key from a peer's base64 public key.
    #[flutter_rust_bridge::frb(sync)]
    pub fn derive_shared_key(&self, peer_public_key_base64: String) -> Option<Vec<u8>> {
        self.inner
            .derive_shared_key(&peer_public_key_base64)
            .map(|k| k.to_vec())
    }
}

/// Fingerprint of a peer's base64 public key (no key exchange needed).
#[flutter_rust_bridge::frb(sync)]
pub fn peer_fingerprint(base64_key: String) -> Option<String> {
    Encryption::peer_fingerprint(&base64_key)
}

/// Random 12-byte base nonce for a file transfer session.
#[flutter_rust_bridge::frb(sync)]
pub fn generate_base_nonce() -> Vec<u8> {
    Encryption::generate_base_nonce().to_vec()
}

/// Lowercase hex SHA-256 of `data`.
#[flutter_rust_bridge::frb(sync)]
pub fn sha256_hex(data: Vec<u8>) -> String {
    Encryption::sha256_hex(&data)
}

/// Encrypt one chunk → `nonce(12) | ciphertext | tag(16)`.
///
/// **Async on purpose** (no `frb(sync)`): FRB dispatches this onto its Rust
/// worker-thread pool instead of the caller (main) isolate, so the Dart event
/// loop stays free to drive the socket while AES-256-GCM runs. That network↔crypto
/// overlap is what lifts encrypted TCP throughput from ~17 MB/s toward the
/// network-bound ~45 MB/s (see `_encryptedBody` / `_handleUpload`).
pub fn encrypt_chunk(
    data: Vec<u8>,
    key: Vec<u8>,
    chunk_index: u64,
    base_nonce: Vec<u8>,
) -> Option<Vec<u8>> {
    let k: [u8; 32] = key.try_into().ok()?;
    let n: [u8; 12] = base_nonce.try_into().ok()?;
    Encryption::encrypt_chunk(&data, &k, chunk_index, &n)
}

/// Decrypt one chunk from combined form. **Async on purpose** — see
/// [`encrypt_chunk`]; runs on FRB's worker pool so decrypt overlaps socket recv.
pub fn decrypt_chunk(
    data: Vec<u8>,
    key: Vec<u8>,
    chunk_index: u64,
    base_nonce: Vec<u8>,
) -> Option<Vec<u8>> {
    let k: [u8; 32] = key.try_into().ok()?;
    let n: [u8; 12] = base_nonce.try_into().ok()?;
    Encryption::decrypt_chunk(&data, &k, chunk_index, &n)
}
