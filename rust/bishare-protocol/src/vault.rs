//! Vault — the keys, envelopes and signatures of BIShare Drive.
//!
//! This module is the canonical implementation of `VAULT-SPEC.md` (next to
//! this crate's `Cargo.toml`). The browser has a byte-compatible TypeScript
//! copy (`bishare-web/src/lib/vault/crypto.ts`) and the app reaches this code
//! through flutter_rust_bridge; the three are pinned to each other by the
//! vectors this module's tests write to
//! `bishare-flutter/test/fixtures/vault_vectors.json`.
//!
//! In short: a 32-byte vault key `VK` seals every name and folder under
//! `K_meta = HKDF(VK)`, every file's bytes under its own random key (a BSE2
//! container), and travels only in sealed form — a key copy opened with a half
//! the server hands out at sign-in, or a grant box between two devices. Each
//! device signs its requests with an Ed25519 key that never leaves it.
//! Nothing here returns plaintext from a failed authentication.

use std::fmt;

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

pub const KEY_SIZE: usize = 32;
pub const NONCE_SIZE: usize = 12;
pub const TAG_SIZE: usize = 16;
/// Random bytes behind a vault id or an object id.
pub const ID_SIZE: usize = 16;
/// A vault id: 16 bytes as lowercase base32 without padding.
pub const VAULT_ID_LEN: usize = 26;
/// An object id or a device id: 16 bytes as base64url without padding.
pub const SHORT_ID_LEN: usize = 22;
/// "BSVK" ‖ version ‖ nonce ‖ VK ‖ tag.
pub const KEY_COPY_SIZE: usize = 4 + 1 + NONCE_SIZE + KEY_SIZE + TAG_SIZE;
/// `v` in the sealed metadata JSON.
pub const META_VERSION: u32 = 1;
/// The scheme name in the Authorization header.
pub const AUTH_SCHEME: &str = "BIShare-Vault";
/// Seconds a request's `ts` may differ from the server's clock.
pub const REQUEST_WINDOW_SECS: i64 = 300;
/// Bytes of HMAC output kept in a dedupe tag.
pub const DEDUPE_TAG_SIZE: usize = 16;

const KEY_COPY_MAGIC: &[u8; 4] = b"BSVK";
const KEY_COPY_VERSION: u8 = 1;
const ZERO_SALT: [u8; 32] = [0u8; 32];
const INFO_KID: &[u8] = b"bishare-vault-kid-v1";
const INFO_META: &[u8] = b"bishare-vault-meta-v1";
const INFO_BACKUP: &[u8] = b"bishare-vault-backup-v1";
const INFO_THUMB: &[u8] = b"bishare-vault-thumb-v1";
const INFO_GRANT: &[u8] = b"bishare-vault-grant-v1";
const INFO_DEDUPE: &[u8] = b"bishare-vault-dedupe-v1";
const AAD_META: &str = "bishare-vault-meta-v1";
const AAD_THUMB: &str = "bishare-vault-thumb-v1";
const AAD_DEVICE: &str = "bishare-vault-device-v1";
/// Longest device name a writer emits, in characters.
pub const DEVICE_NAME_MAX: usize = 100;
const REQ_PREFIX: &str = "bishare-vault-req-v1";
const NONCE_PREFIX: &[u8] = b"bishare-vault-nonce-v1";
const PHRASE_WORDS: usize = 24;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VaultError {
    /// A key, nonce or public key of the wrong length.
    InvalidKey,
    InvalidVaultId,
    InvalidObjectId,
    /// A box shorter than nonce + tag.
    SealedBoxTooShort,
    /// GCM tag mismatch: wrong key, wrong AAD, or tampered bytes.
    AuthFailed,
    /// Not 65 bytes, or the magic or version is wrong.
    BadKeyCopy,
    /// An X25519 or Ed25519 public key that cannot be used.
    BadPublicKey,
    /// Not 24 valid English words with a correct checksum.
    BadPhrase,
    /// Metadata that breaks a rule of the spec (the reason is for logs).
    BadMeta(String),
    BadSignature,
    BadAuthorization,
    /// The vault key received does not match the account's key check.
    KeyCheckMismatch,
    /// Compressed bytes that do not inflate to exactly the sealed size.
    BadCompression,
}

impl fmt::Display for VaultError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidKey => write!(f, "invalid key length"),
            Self::InvalidVaultId => write!(f, "invalid vault id"),
            Self::InvalidObjectId => write!(f, "invalid object id"),
            Self::SealedBoxTooShort => write!(f, "sealed box too short"),
            Self::AuthFailed => write!(f, "could not open sealed box"),
            Self::BadKeyCopy => write!(f, "not a vault key copy"),
            Self::BadPublicKey => write!(f, "bad public key"),
            Self::BadPhrase => write!(f, "not a valid recovery phrase"),
            Self::BadMeta(why) => write!(f, "bad metadata: {why}"),
            Self::BadSignature => write!(f, "bad signature"),
            Self::BadAuthorization => write!(f, "bad authorization header"),
            Self::KeyCheckMismatch => write!(f, "key does not belong to this vault"),
            Self::BadCompression => write!(f, "compressed bytes do not match the file"),
        }
    }
}

impl std::error::Error for VaultError {}

type Result<T> = std::result::Result<T, VaultError>;

// ── encoding ────────────────────────────────────────────────────────────────

pub fn b64u(bytes: &[u8]) -> String {
    URL_SAFE_NO_PAD.encode(bytes)
}

pub fn from_b64u(s: &str) -> Option<Vec<u8>> {
    URL_SAFE_NO_PAD.decode(s).ok()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Lowercase RFC 4648 base32 without padding — the text form of a vault id.
pub fn base32_lower(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 32] = b"abcdefghijklmnopqrstuvwxyz234567";
    let mut out = String::with_capacity(bytes.len() * 8 / 5 + 1);
    let mut acc: u32 = 0;
    let mut bits = 0;
    for &b in bytes {
        acc = (acc << 8) | u32::from(b);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            out.push(ALPHABET[((acc >> bits) & 31) as usize] as char);
        }
    }
    if bits > 0 {
        out.push(ALPHABET[((acc << (5 - bits)) & 31) as usize] as char);
    }
    out
}

/// The text form of a new vault id, from 16 random bytes.
pub fn vault_id_from_bytes(bytes: &[u8; ID_SIZE]) -> String {
    base32_lower(bytes)
}

pub fn is_vault_id(s: &str) -> bool {
    s.len() == VAULT_ID_LEN && s.bytes().all(|b| matches!(b, b'a'..=b'z' | b'2'..=b'7'))
}

pub fn is_object_id(s: &str) -> bool {
    s.len() == SHORT_ID_LEN && from_b64u(s).map(|v| v.len() == ID_SIZE).unwrap_or(false)
}

fn check_ids(vault_id: &str, object_id: &str) -> Result<()> {
    if !is_vault_id(vault_id) {
        return Err(VaultError::InvalidVaultId);
    }
    if !is_object_id(object_id) {
        return Err(VaultError::InvalidObjectId);
    }
    Ok(())
}

// ── primitives ──────────────────────────────────────────────────────────────

fn random<const N: usize>() -> [u8; N] {
    let mut out = [0u8; N];
    rand::rngs::OsRng.fill_bytes(&mut out);
    out
}

fn hkdf(ikm: &[u8], salt: &[u8], info: &[u8], out: &mut [u8]) {
    Hkdf::<Sha256>::new(Some(salt), ikm)
        .expand(info, out)
        .expect("HKDF output length is always small here");
}

fn hkdf32(ikm: &[u8], info: &[u8]) -> [u8; KEY_SIZE] {
    let mut out = [0u8; KEY_SIZE];
    hkdf(ikm, &ZERO_SALT, info, &mut out);
    out
}

/// nonce ‖ AES-256-GCM(key, nonce, plain, aad) — the "box" of the spec.
fn seal(key: &[u8; KEY_SIZE], nonce: &[u8; NONCE_SIZE], plain: &[u8], aad: &[u8]) -> Vec<u8> {
    let cipher = Aes256Gcm::new_from_slice(key).expect("32-byte key");
    let ct = cipher
        .encrypt(Nonce::from_slice(nonce), Payload { msg: plain, aad })
        .expect("AES-GCM encryption of an in-memory message cannot fail");
    let mut out = Vec::with_capacity(NONCE_SIZE + ct.len());
    out.extend_from_slice(nonce);
    out.extend_from_slice(&ct);
    out
}

fn open(key: &[u8; KEY_SIZE], boxed: &[u8], aad: &[u8]) -> Result<Vec<u8>> {
    if boxed.len() < NONCE_SIZE + TAG_SIZE {
        return Err(VaultError::SealedBoxTooShort);
    }
    let cipher = Aes256Gcm::new_from_slice(key).expect("32-byte key");
    cipher
        .decrypt(
            Nonce::from_slice(&boxed[..NONCE_SIZE]),
            Payload { msg: &boxed[NONCE_SIZE..], aad },
        )
        .map_err(|_| VaultError::AuthFailed)
}

fn nonce_or_random(nonce: Option<[u8; NONCE_SIZE]>) -> [u8; NONCE_SIZE] {
    nonce.unwrap_or_else(random)
}

// ── vault key ───────────────────────────────────────────────────────────────

pub fn generate_vault_key() -> [u8; KEY_SIZE] {
    random()
}

pub fn generate_file_key() -> [u8; KEY_SIZE] {
    random()
}

pub fn generate_object_id() -> String {
    b64u(&random::<ID_SIZE>())
}

/// `b64u(HKDF(VK, "bishare-vault-kid-v1", 16))`: what the server knows about
/// VK, and what a device checks a received VK against.
pub fn key_check(vault_key: &[u8; KEY_SIZE]) -> String {
    let mut out = [0u8; 16];
    hkdf(vault_key, &ZERO_SALT, INFO_KID, &mut out);
    b64u(&out)
}

/// `K_meta`, the key every name and folder is sealed under.
pub fn meta_key(vault_key: &[u8; KEY_SIZE]) -> [u8; KEY_SIZE] {
    hkdf32(vault_key, INFO_META)
}

/// The key a file's thumbnail is sealed under, from that file's key.
/// `K_dedupe`: keys the dedupe tag. Like every key here, it never leaves the device.
pub fn dedupe_key(vault_key: &[u8; KEY_SIZE]) -> [u8; KEY_SIZE] {
    hkdf32(vault_key, INFO_DEDUPE)
}

/// The tag sent with an upload so the server can find a blob with the same
/// content in this vault, and only this vault: `b64u(HMAC-SHA256(K_dedupe, h)[0..16))`
/// where `h` is the 32-byte SHA-256 of the plaintext (the `h` of the metadata).
pub fn dedupe_tag(dedupe_key: &[u8; KEY_SIZE], plaintext_hash: &[u8; 32]) -> String {
    let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(dedupe_key).expect("HMAC takes a key of any length");
    mac.update(plaintext_hash);
    b64u(&mac.finalize().into_bytes()[..DEDUPE_TAG_SIZE])
}

pub fn thumb_key(file_key: &[u8; KEY_SIZE]) -> [u8; KEY_SIZE] {
    hkdf32(file_key, INFO_THUMB)
}

/// The 24-word BIP-39 English phrase that encodes VK: lowercase words, single
/// spaces.
pub fn phrase_from_key(vault_key: &[u8; KEY_SIZE]) -> String {
    bip39::Mnemonic::from_entropy(vault_key)
        .expect("32 bytes of entropy is a valid mnemonic length")
        .to_string()
}

/// VK from a phrase as a person typed it: case, extra spaces and Unicode
/// compatibility forms are forgiven; a wrong word, a wrong count or a bad
/// checksum is not.
pub fn key_from_phrase(phrase: &str) -> Result<[u8; KEY_SIZE]> {
    let cleaned = phrase
        .split_whitespace()
        .map(str::to_lowercase)
        .collect::<Vec<_>>()
        .join(" ");
    let mnemonic = bip39::Mnemonic::parse_in(bip39::Language::English, cleaned)
        .map_err(|_| VaultError::BadPhrase)?;
    if mnemonic.word_count() != PHRASE_WORDS {
        return Err(VaultError::BadPhrase);
    }
    mnemonic
        .to_entropy()
        .try_into()
        .map_err(|_| VaultError::BadPhrase)
}

// ── key copy ────────────────────────────────────────────────────────────────

fn backup_key(server_half: &[u8; KEY_SIZE]) -> [u8; KEY_SIZE] {
    hkdf32(server_half, INFO_BACKUP)
}

/// The 65-byte copy of VK kept in the person's own Apple or Google account.
/// `nonce` is fixed only by tests.
pub fn seal_key_copy(
    server_half: &[u8; KEY_SIZE],
    vault_id: &str,
    vault_key: &[u8; KEY_SIZE],
    nonce: Option<[u8; NONCE_SIZE]>,
) -> Result<Vec<u8>> {
    if !is_vault_id(vault_id) {
        return Err(VaultError::InvalidVaultId);
    }
    let mut out = Vec::with_capacity(KEY_COPY_SIZE);
    out.extend_from_slice(KEY_COPY_MAGIC);
    out.push(KEY_COPY_VERSION);
    out.extend_from_slice(&seal(
        &backup_key(server_half),
        &nonce_or_random(nonce),
        vault_key,
        vault_id.as_bytes(),
    ));
    debug_assert_eq!(out.len(), KEY_COPY_SIZE);
    Ok(out)
}

/// VK from a key copy and the server half. The caller still compares
/// [`key_check`] of the result with the server's value.
pub fn open_key_copy(
    server_half: &[u8; KEY_SIZE],
    vault_id: &str,
    key_copy: &[u8],
) -> Result<[u8; KEY_SIZE]> {
    if !is_vault_id(vault_id) {
        return Err(VaultError::InvalidVaultId);
    }
    if key_copy.len() != KEY_COPY_SIZE
        || &key_copy[..4] != KEY_COPY_MAGIC
        || key_copy[4] != KEY_COPY_VERSION
    {
        return Err(VaultError::BadKeyCopy);
    }
    let plain = open(&backup_key(server_half), &key_copy[5..], vault_id.as_bytes())?;
    plain.try_into().map_err(|_| VaultError::BadKeyCopy)
}

// ── object metadata ─────────────────────────────────────────────────────────

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ObjectKind {
    File,
    Dir,
}

impl ObjectKind {
    fn wire(self) -> &'static str {
        match self {
            Self::File => "file",
            Self::Dir => "dir",
        }
    }
}

/// How a file's bytes were transformed before they were sealed with BSE2.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Compression {
    /// Raw DEFLATE (RFC 1951): no zlib or gzip header.
    Deflate,
}

impl Compression {
    fn wire(self) -> &'static str {
        match self {
            Self::Deflate => "deflate",
        }
    }
}

/// What is sealed about one file or folder. Only `kind`, `name`, `parent` and
/// `mtime_ms` apply to a folder.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ObjectMeta {
    pub kind: ObjectKind,
    pub name: String,
    /// The parent object id, or `None` at the root.
    pub parent: Option<String>,
    /// Modification time, Unix milliseconds.
    pub mtime_ms: i64,
    /// Plaintext size in bytes (files).
    pub size: Option<u64>,
    /// MIME type (files).
    pub mime: Option<String>,
    /// The BSE2 key for the file's bytes (files).
    pub file_key: Option<[u8; KEY_SIZE]>,
    /// SHA-256 of the plaintext (files).
    pub hash: Option<[u8; 32]>,
    /// Set when the bytes in the blob were compressed before sealing (files).
    /// `size` and `hash` stay those of the uncompressed file.
    pub compression: Option<Compression>,
}

/// The JSON as written: this key order, nothing else.
#[derive(Serialize, Deserialize)]
struct MetaWire {
    v: u32,
    k: String,
    n: String,
    p: Option<String>,
    m: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    s: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    t: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    fk: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    h: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    z: Option<String>,
}

fn bad(why: &str) -> VaultError {
    VaultError::BadMeta(why.to_string())
}

impl ObjectMeta {
    fn validate(&self) -> Result<()> {
        if self.name.is_empty() {
            return Err(bad("empty name"));
        }
        if self.name.contains('/') || self.name.contains('\0') {
            return Err(bad("name contains / or NUL"));
        }
        if let Some(p) = &self.parent {
            if !is_object_id(p) {
                return Err(bad("parent is not an object id"));
            }
        }
        if self.kind == ObjectKind::File {
            if self.size.is_none() {
                return Err(bad("file without size"));
            }
            if self.mime.as_deref().map_or(true, str::is_empty) {
                return Err(bad("file without mime type"));
            }
            if self.file_key.is_none() {
                return Err(bad("file without file key"));
            }
            if self.hash.is_none() {
                return Err(bad("file without hash"));
            }
        }
        Ok(())
    }

    /// The canonical JSON of the spec. A folder's file-only fields are
    /// dropped even if set.
    pub fn to_json(&self) -> Result<String> {
        self.validate()?;
        let file = self.kind == ObjectKind::File;
        let wire = MetaWire {
            v: META_VERSION,
            k: self.kind.wire().to_string(),
            n: self.name.clone(),
            p: self.parent.clone(),
            m: self.mtime_ms,
            s: if file { self.size } else { None },
            t: if file { self.mime.clone() } else { None },
            fk: if file { self.file_key.map(|k| b64u(&k)) } else { None },
            h: if file { self.hash.map(|h| b64u(&h)) } else { None },
            z: if file { self.compression.map(|c| c.wire().to_string()) } else { None },
        };
        serde_json::to_string(&wire).map_err(|e| bad(&e.to_string()))
    }

    /// Reads any JSON serialization; unknown keys are ignored, but an unknown
    /// `z` is refused: those bytes could not be read back.
    pub fn from_json(json: &str) -> Result<Self> {
        // Never the parser's own text: it can quote decrypted values (a name)
        // into a log. A category is enough to tell what went wrong.
        let wire: MetaWire = serde_json::from_str(json).map_err(|e| {
            bad(match e.classify() {
                serde_json::error::Category::Data => "a field is missing, doubled or of the wrong type",
                _ => "not JSON",
            })
        })?;
        if wire.v != META_VERSION {
            return Err(bad("unknown version"));
        }
        let kind = match wire.k.as_str() {
            "file" => ObjectKind::File,
            "dir" => ObjectKind::Dir,
            _ => return Err(bad("unknown kind")),
        };
        let key32 = |field: Option<String>, what: &str| -> Result<Option<[u8; 32]>> {
            match field {
                None => Ok(None),
                Some(s) => from_b64u(&s)
                    .and_then(|v| <[u8; 32]>::try_from(v).ok())
                    .map(Some)
                    .ok_or_else(|| bad(&format!("{what} is not 32 bytes"))),
            }
        };
        let file = kind == ObjectKind::File;
        let compression = match (file, wire.z.as_deref()) {
            (false, _) | (true, None) => None,
            (true, Some("deflate")) => Some(Compression::Deflate),
            (true, Some(_)) => return Err(bad("unknown compression")),
        };
        let meta = ObjectMeta {
            kind,
            name: wire.n,
            parent: wire.p,
            mtime_ms: wire.m,
            size: if file { wire.s } else { None },
            mime: if file { wire.t } else { None },
            file_key: if file { key32(wire.fk, "file key")? } else { None },
            hash: if file { key32(wire.h, "hash")? } else { None },
            compression,
        };
        meta.validate()?;
        Ok(meta)
    }
}

// ── compression ─────────────────────────────────────────────────────────────

/// Raw DEFLATE at level 6. Any encoder is allowed to write `"z":"deflate"`
/// (the browser uses CompressionStream); readers accept any valid stream.
pub fn deflate_raw(data: &[u8]) -> Vec<u8> {
    miniz_oxide::deflate::compress_to_vec(data, 6)
}

/// Inflate raw DEFLATE that must give exactly `expected_len` bytes (the
/// sealed `s`). Output past that length is never produced, so a crafted
/// stream cannot expand without bound.
pub fn inflate_raw(data: &[u8], expected_len: usize) -> Result<Vec<u8>> {
    let out = miniz_oxide::inflate::decompress_to_vec_with_limit(data, expected_len)
        .map_err(|_| VaultError::BadCompression)?;
    if out.len() != expected_len {
        return Err(VaultError::BadCompression);
    }
    Ok(out)
}

fn meta_aad(vault_id: &str, object_id: &str) -> Result<Vec<u8>> {
    check_ids(vault_id, object_id)?;
    Ok(format!("{AAD_META}|{vault_id}|{object_id}").into_bytes())
}

fn thumb_aad(vault_id: &str, object_id: &str) -> Result<Vec<u8>> {
    check_ids(vault_id, object_id)?;
    Ok(format!("{AAD_THUMB}|{vault_id}|{object_id}").into_bytes())
}

/// `enc_meta` for one object: b64u of a box over the canonical JSON, bound to
/// the vault and object ids. `nonce` is fixed only by tests.
pub fn seal_meta(
    meta_key: &[u8; KEY_SIZE],
    vault_id: &str,
    object_id: &str,
    meta: &ObjectMeta,
    nonce: Option<[u8; NONCE_SIZE]>,
) -> Result<String> {
    let aad = meta_aad(vault_id, object_id)?;
    let json = meta.to_json()?;
    Ok(b64u(&seal(meta_key, &nonce_or_random(nonce), json.as_bytes(), &aad)))
}

pub fn open_meta(
    meta_key: &[u8; KEY_SIZE],
    vault_id: &str,
    object_id: &str,
    enc_meta: &str,
) -> Result<ObjectMeta> {
    let aad = meta_aad(vault_id, object_id)?;
    let boxed = from_b64u(enc_meta).ok_or(VaultError::SealedBoxTooShort)?;
    let plain = open(meta_key, &boxed, &aad)?;
    let json = String::from_utf8(plain).map_err(|_| bad("not UTF-8"))?;
    ObjectMeta::from_json(&json)
}

// ── device names ────────────────────────────────────────────────────────────

fn device_aad(vault_id: &str, device_id: &str) -> Result<Vec<u8>> {
    check_ids(vault_id, device_id)?;
    Ok(format!("{AAD_DEVICE}|{vault_id}|{device_id}").into_bytes())
}

fn check_device_name(name: &str) -> Result<()> {
    if name.is_empty() || name.contains('\0') {
        return Err(bad("device name"));
    }
    Ok(())
}

/// `enc_name` for one device: b64u of a box over the name under `K_meta`,
/// bound to the vault and device ids. `nonce` is fixed only by tests.
pub fn seal_device_name(
    meta_key: &[u8; KEY_SIZE],
    vault_id: &str,
    device_id: &str,
    name: &str,
    nonce: Option<[u8; NONCE_SIZE]>,
) -> Result<String> {
    check_device_name(name)?;
    if name.chars().count() > DEVICE_NAME_MAX {
        return Err(bad("device name too long"));
    }
    let aad = device_aad(vault_id, device_id)?;
    Ok(b64u(&seal(meta_key, &nonce_or_random(nonce), name.as_bytes(), &aad)))
}

pub fn open_device_name(
    meta_key: &[u8; KEY_SIZE],
    vault_id: &str,
    device_id: &str,
    enc_name: &str,
) -> Result<String> {
    let aad = device_aad(vault_id, device_id)?;
    let boxed = from_b64u(enc_name).ok_or(VaultError::SealedBoxTooShort)?;
    let plain = open(meta_key, &boxed, &aad)?;
    let name = String::from_utf8(plain).map_err(|_| bad("not UTF-8"))?;
    check_device_name(&name)?;
    Ok(name)
}

// ── thumbnails ──────────────────────────────────────────────────────────────

/// The stored bytes of a thumbnail: a box under the file's thumb key, bound
/// to the vault and object ids.
pub fn seal_thumbnail(
    file_key: &[u8; KEY_SIZE],
    vault_id: &str,
    object_id: &str,
    jpeg: &[u8],
    nonce: Option<[u8; NONCE_SIZE]>,
) -> Result<Vec<u8>> {
    let aad = thumb_aad(vault_id, object_id)?;
    Ok(seal(&thumb_key(file_key), &nonce_or_random(nonce), jpeg, &aad))
}

pub fn open_thumbnail(
    file_key: &[u8; KEY_SIZE],
    vault_id: &str,
    object_id: &str,
    sealed: &[u8],
) -> Result<Vec<u8>> {
    let aad = thumb_aad(vault_id, object_id)?;
    open(&thumb_key(file_key), sealed, &aad)
}

// ── the grant: VK from one device to another ────────────────────────────────

/// A one-off X25519 key pair for a hand-off. Neither side keeps it.
pub struct GrantKey {
    secret: StaticSecret,
    public: PublicKey,
}

impl GrantKey {
    pub fn generate() -> Self {
        Self::from_bytes(&random())
    }

    pub fn from_bytes(secret: &[u8; KEY_SIZE]) -> Self {
        let secret = StaticSecret::from(*secret);
        let public = PublicKey::from(&secret);
        Self { secret, public }
    }

    pub fn public_bytes(&self) -> [u8; KEY_SIZE] {
        self.public.to_bytes()
    }

    pub fn secret_bytes(&self) -> [u8; KEY_SIZE] {
        self.secret.to_bytes()
    }

    fn wrap_key(
        &self,
        their_pub: &[u8; KEY_SIZE],
        new_pub: &[u8; KEY_SIZE],
        granter_pub: &[u8; KEY_SIZE],
    ) -> Result<[u8; KEY_SIZE]> {
        let shared = self.secret.diffie_hellman(&PublicKey::from(*their_pub));
        if !shared.was_contributory() {
            return Err(VaultError::BadPublicKey);
        }
        let mut salt = [0u8; 64];
        salt[..KEY_SIZE].copy_from_slice(new_pub);
        salt[KEY_SIZE..].copy_from_slice(granter_pub);
        let mut out = [0u8; KEY_SIZE];
        hkdf(shared.as_bytes(), &salt, INFO_GRANT, &mut out);
        Ok(out)
    }
}

/// The granter (who has VK) seals it for the new device whose X25519 public
/// key it read from a QR code. Returns the box; `mine.public_bytes()` travels
/// with it.
pub fn grant(
    vault_key: &[u8; KEY_SIZE],
    vault_id: &str,
    mine: &GrantKey,
    new_pub: &[u8; KEY_SIZE],
    nonce: Option<[u8; NONCE_SIZE]>,
) -> Result<Vec<u8>> {
    if !is_vault_id(vault_id) {
        return Err(VaultError::InvalidVaultId);
    }
    let wrap = mine.wrap_key(new_pub, new_pub, &mine.public_bytes())?;
    Ok(seal(&wrap, &nonce_or_random(nonce), vault_key, vault_id.as_bytes()))
}

/// The new device opens a grant and accepts VK only if it matches the
/// account's key check.
pub fn accept_grant(
    vault_id: &str,
    mine: &GrantKey,
    granter_pub: &[u8; KEY_SIZE],
    boxed: &[u8],
    expected_key_check: &str,
) -> Result<[u8; KEY_SIZE]> {
    if !is_vault_id(vault_id) {
        return Err(VaultError::InvalidVaultId);
    }
    let wrap = mine.wrap_key(granter_pub, &mine.public_bytes(), granter_pub)?;
    let plain = open(&wrap, boxed, vault_id.as_bytes())?;
    let key: [u8; KEY_SIZE] = plain.try_into().map_err(|_| VaultError::AuthFailed)?;
    if key_check(&key) != expected_key_check {
        return Err(VaultError::KeyCheckMismatch);
    }
    Ok(key)
}

// ── device key, sign-in nonce and signed requests ───────────────────────────

/// The Ed25519 key a device signs its requests with. Only the 32-byte seed is
/// stored, in the platform's secure storage.
pub struct DeviceKey {
    signing: SigningKey,
}

/// `b64u(SHA256(public key)[0..16))`.
pub fn device_id_of(public_key: &[u8; KEY_SIZE]) -> String {
    b64u(&Sha256::digest(public_key)[..ID_SIZE])
}

/// The nonce a device puts into its Apple or Google sign-in request.
pub fn signin_nonce(public_key: &[u8; KEY_SIZE]) -> String {
    let mut h = Sha256::new();
    h.update(NONCE_PREFIX);
    h.update(public_key);
    b64u(&h.finalize())
}

/// The bytes a request signature covers.
pub fn request_message(method: &str, path_and_query: &str, ts: i64, body: &[u8]) -> String {
    format!(
        "{REQ_PREFIX}\n{}\n{path_and_query}\n{ts}\n{}",
        method.to_ascii_uppercase(),
        hex(&Sha256::digest(body))
    )
}

impl DeviceKey {
    pub fn generate() -> Self {
        Self::from_seed(&random())
    }

    pub fn from_seed(seed: &[u8; KEY_SIZE]) -> Self {
        Self { signing: SigningKey::from_bytes(seed) }
    }

    pub fn seed(&self) -> [u8; KEY_SIZE] {
        self.signing.to_bytes()
    }

    pub fn public_bytes(&self) -> [u8; KEY_SIZE] {
        self.signing.verifying_key().to_bytes()
    }

    pub fn device_id(&self) -> String {
        device_id_of(&self.public_bytes())
    }

    pub fn signin_nonce(&self) -> String {
        signin_nonce(&self.public_bytes())
    }

    /// b64u of the signature over [`request_message`].
    pub fn sign_request(&self, method: &str, path_and_query: &str, ts: i64, body: &[u8]) -> String {
        let message = request_message(method, path_and_query, ts, body);
        b64u(&self.signing.sign(message.as_bytes()).to_bytes())
    }

    /// The complete `Authorization` header value for one request.
    pub fn authorization(
        &self,
        vault_id: &str,
        method: &str,
        path_and_query: &str,
        ts: i64,
        body: &[u8],
    ) -> Result<String> {
        if !is_vault_id(vault_id) {
            return Err(VaultError::InvalidVaultId);
        }
        Ok(Authorization {
            vault_id: vault_id.to_string(),
            device_id: self.device_id(),
            ts,
            signature: self.sign_request(method, path_and_query, ts, body),
        }
        .header())
    }
}

/// Checks a request signature against a device public key. What the server
/// does, and what the tests use to prove the three implementations sign the
/// same bytes.
pub fn verify_request(
    public_key: &[u8; KEY_SIZE],
    method: &str,
    path_and_query: &str,
    ts: i64,
    body: &[u8],
    signature_b64u: &str,
) -> Result<()> {
    let key = VerifyingKey::from_bytes(public_key).map_err(|_| VaultError::BadPublicKey)?;
    let sig: [u8; 64] = from_b64u(signature_b64u)
        .and_then(|v| v.try_into().ok())
        .ok_or(VaultError::BadSignature)?;
    let message = request_message(method, path_and_query, ts, body);
    key.verify_strict(message.as_bytes(), &Signature::from_bytes(&sig))
        .map_err(|_| VaultError::BadSignature)
}

/// The fields of the `Authorization: BIShare-Vault …` header.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Authorization {
    pub vault_id: String,
    pub device_id: String,
    pub ts: i64,
    pub signature: String,
}

impl Authorization {
    pub fn header(&self) -> String {
        format!(
            "{AUTH_SCHEME} v=1,vault={},device={},ts={},sig={}",
            self.vault_id, self.device_id, self.ts, self.signature
        )
    }

    pub fn parse(header: &str) -> Result<Self> {
        let rest = header
            .strip_prefix(AUTH_SCHEME)
            .and_then(|r| r.strip_prefix(' '))
            .ok_or(VaultError::BadAuthorization)?;
        let mut v = None;
        let mut vault_id = None;
        let mut device_id = None;
        let mut ts = None;
        let mut signature = None;
        for field in rest.split(',') {
            let (k, val) = field.split_once('=').ok_or(VaultError::BadAuthorization)?;
            let slot = match k {
                "v" => &mut v,
                "vault" => &mut vault_id,
                "device" => &mut device_id,
                "ts" => &mut ts,
                "sig" => &mut signature,
                _ => return Err(VaultError::BadAuthorization),
            };
            if slot.replace(val.to_string()).is_some() {
                return Err(VaultError::BadAuthorization);
            }
        }
        if v.as_deref() != Some("1") {
            return Err(VaultError::BadAuthorization);
        }
        let vault_id = vault_id.filter(|s| is_vault_id(s)).ok_or(VaultError::BadAuthorization)?;
        let device_id = device_id
            .filter(|s| s.len() == SHORT_ID_LEN && from_b64u(s).map_or(false, |b| b.len() == ID_SIZE))
            .ok_or(VaultError::BadAuthorization)?;
        let ts = ts
            .and_then(|s| s.parse::<i64>().ok())
            .ok_or(VaultError::BadAuthorization)?;
        let signature = signature
            .filter(|s| from_b64u(s).map_or(false, |b| b.len() == 64))
            .ok_or(VaultError::BadAuthorization)?;
        Ok(Self { vault_id, device_id, ts, signature })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;
    use serde_json::json;

    /// Where the vectors live; `cargo test -- --ignored write_vectors` rewrites it.
    const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../test/fixtures/vault_vectors.json");

    fn seq<const N: usize>(start: u8) -> [u8; N] {
        let mut out = [0u8; N];
        for (i, b) in out.iter_mut().enumerate() {
            *b = start.wrapping_add(i as u8);
        }
        out
    }

    struct Inputs {
        vault_id: String,
        vk: [u8; 32],
        server_half: [u8; 32],
        key_copy_nonce: [u8; 12],
        device_seed: [u8; 32],
        dir_id: String,
        file_id: String,
        file_key: [u8; 32],
        plaintext: Vec<u8>,
        meta_nonce: [u8; 12],
        dir_nonce: [u8; 12],
        thumbnail: [u8; 48],
        thumb_nonce: [u8; 12],
        new_priv: [u8; 32],
        granter_priv: [u8; 32],
        grant_nonce: [u8; 12],
        req_method: &'static str,
        req_path: String,
        req_ts: i64,
        req_body: &'static [u8],
    }

    fn inputs() -> Inputs {
        let vault_id = vault_id_from_bytes(&seq::<16>(0x00));
        Inputs {
            req_path: format!("/api/v1/vault/{vault_id}/ops?x=1"),
            vault_id,
            vk: seq(0x10),
            server_half: seq(0x30),
            key_copy_nonce: seq(0x50),
            device_seed: seq(0x60),
            dir_id: b64u(&seq::<16>(0xa0)),
            file_id: b64u(&seq::<16>(0x70)),
            file_key: seq(0x80),
            plaintext: "BIShare vault vector — the bytes of a file.\n".repeat(3).into_bytes(),
            meta_nonce: seq(0x90),
            dir_nonce: seq(0x98),
            thumbnail: seq(0xc0),
            thumb_nonce: seq(0xb0),
            new_priv: seq(0xd0),
            granter_priv: seq(0xe0),
            grant_nonce: seq(0xf0),
            req_method: "POST",
            req_ts: 1_728_000_000,
            req_body: br#"{"ops":[]}"#,
        }
    }

    fn file_meta(i: &Inputs) -> ObjectMeta {
        ObjectMeta {
            kind: ObjectKind::File,
            name: "Résumé 📄 final.pdf".to_string(),
            parent: Some(i.dir_id.clone()),
            mtime_ms: 1_728_000_000_123,
            size: Some(i.plaintext.len() as u64),
            mime: Some("application/pdf".to_string()),
            file_key: Some(i.file_key),
            hash: Some(Sha256::digest(&i.plaintext).into()),
            compression: None,
        }
    }

    /// A CSV-like text that DEFLATE shrinks a lot.
    fn compressible_plaintext() -> Vec<u8> {
        (0..40).map(|n| format!("{n},BIShare vault compression vector,{}\n", n * 7)).collect::<String>().into_bytes()
    }

    fn compressed_meta(i: &Inputs) -> ObjectMeta {
        let plain = compressible_plaintext();
        ObjectMeta {
            kind: ObjectKind::File,
            name: "inventory.csv".to_string(),
            parent: Some(i.dir_id.clone()),
            mtime_ms: 1_728_000_000_456,
            size: Some(plain.len() as u64),
            mime: Some("text/csv".to_string()),
            file_key: Some(seq(0x88)),
            hash: Some(Sha256::digest(&plain).into()),
            compression: Some(Compression::Deflate),
        }
    }

    fn dir_meta() -> ObjectMeta {
        ObjectMeta {
            kind: ObjectKind::Dir,
            name: "Photos 2026".to_string(),
            parent: None,
            mtime_ms: 1_727_000_000_000,
            size: None,
            mime: None,
            file_key: None,
            hash: None,
            compression: None,
        }
    }

    fn vectors() -> serde_json::Value {
        let i = inputs();
        let k_meta = meta_key(&i.vk);
        let device = DeviceKey::from_seed(&i.device_seed);
        let fm = file_meta(&i);
        let dm = dir_meta();
        let new_key = GrantKey::from_bytes(&i.new_priv);
        let granter = GrantKey::from_bytes(&i.granter_priv);
        let wrap = granter
            .wrap_key(&new_key.public_bytes(), &new_key.public_bytes(), &granter.public_bytes())
            .unwrap();
        let signature = device.sign_request(i.req_method, &i.req_path, i.req_ts, i.req_body);
        let k_dedupe = dedupe_key(&i.vk);
        let cm = compressed_meta(&i);
        let c_plain = compressible_plaintext();
        json!({
            "note": "Written by the Rust tests in bishare-flutter/rust/bishare-protocol/src/vault.rs (VAULT-SPEC.md). Binary values are base64url without padding; 'seq' inputs are consecutive bytes.",
            "vaultId": i.vault_id,
            "vaultKey": b64u(&i.vk),
            "keyCheck": key_check(&i.vk),
            "metaKey": b64u(&k_meta),
            "phrase": phrase_from_key(&i.vk),
            "keyCopy": {
                "serverHalf": b64u(&i.server_half),
                "backupKey": b64u(&backup_key(&i.server_half)),
                "nonce": b64u(&i.key_copy_nonce),
                "blob": b64u(&seal_key_copy(&i.server_half, &i.vault_id, &i.vk, Some(i.key_copy_nonce)).unwrap()),
            },
            "device": {
                "seed": b64u(&i.device_seed),
                "publicKey": b64u(&device.public_bytes()),
                "deviceId": device.device_id(),
                "signinNonce": device.signin_nonce(),
                "name": "Cakra's iPhone 📱",
                "nameNonce": b64u(&seq::<12>(0x58)),
                "encName": seal_device_name(&k_meta, &i.vault_id, &device.device_id(), "Cakra's iPhone 📱", Some(seq::<12>(0x58))).unwrap(),
            },
            "request": {
                "method": i.req_method,
                "pathAndQuery": i.req_path,
                "ts": i.req_ts,
                "body": String::from_utf8(i.req_body.to_vec()).unwrap(),
                "bodySha256": hex(&Sha256::digest(i.req_body)),
                "message": request_message(i.req_method, &i.req_path, i.req_ts, i.req_body),
                "signature": signature,
                "authorization": device.authorization(&i.vault_id, i.req_method, &i.req_path, i.req_ts, i.req_body).unwrap(),
            },
            "file": {
                "objectId": i.file_id,
                "fileKey": b64u(&i.file_key),
                "plaintext": b64u(&i.plaintext),
                "meta": {
                    "kind": "file", "name": fm.name, "parent": fm.parent, "mtimeMs": fm.mtime_ms,
                    "size": fm.size, "mime": fm.mime, "hash": b64u(&fm.hash.unwrap()),
                },
                "metaJson": fm.to_json().unwrap(),
                "nonce": b64u(&i.meta_nonce),
                "encMeta": seal_meta(&k_meta, &i.vault_id, &i.file_id, &fm, Some(i.meta_nonce)).unwrap(),
                "thumbKey": b64u(&thumb_key(&i.file_key)),
                "thumbnail": b64u(&i.thumbnail),
                "thumbNonce": b64u(&i.thumb_nonce),
                "encThumbnail": b64u(&seal_thumbnail(&i.file_key, &i.vault_id, &i.file_id, &i.thumbnail, Some(i.thumb_nonce)).unwrap()),
            },
            "dir": {
                "objectId": i.dir_id,
                "meta": { "kind": "dir", "name": dm.name, "parent": null, "mtimeMs": dm.mtime_ms },
                "metaJson": dm.to_json().unwrap(),
                "nonce": b64u(&i.dir_nonce),
                "encMeta": seal_meta(&k_meta, &i.vault_id, &i.dir_id, &dm, Some(i.dir_nonce)).unwrap(),
            },
            "dedupe": {
                "dedupeKey": b64u(&k_dedupe),
                "hash": b64u(&fm.hash.unwrap()),
                "tag": dedupe_tag(&k_dedupe, &fm.hash.unwrap()),
            },
            "compressed": {
                "objectId": b64u(&seq::<16>(0x20)),
                "plaintext": b64u(&c_plain),
                "deflated": b64u(&deflate_raw(&c_plain)),
                "metaJson": cm.to_json().unwrap(),
                "nonce": b64u(&seq::<12>(0x48)),
                "encMeta": seal_meta(&k_meta, &i.vault_id, &b64u(&seq::<16>(0x20)), &cm, Some(seq::<12>(0x48))).unwrap(),
            },
            "grant": {
                "newPriv": b64u(&i.new_priv),
                "newPub": b64u(&new_key.public_bytes()),
                "granterPriv": b64u(&i.granter_priv),
                "granterPub": b64u(&granter.public_bytes()),
                "wrapKey": b64u(&wrap),
                "nonce": b64u(&i.grant_nonce),
                "box": b64u(&grant(&i.vk, &i.vault_id, &granter, &new_key.public_bytes(), Some(i.grant_nonce)).unwrap()),
            },
        })
    }

    fn pretty(v: &serde_json::Value) -> String {
        serde_json::to_string_pretty(v).unwrap() + "\n"
    }

    #[test]
    #[ignore = "rewrites the shared fixture; run on purpose"]
    fn write_vectors() {
        std::fs::write(FIXTURE, pretty(&vectors())).unwrap();
    }

    #[test]
    fn vectors_match_the_fixture() {
        let current = std::fs::read_to_string(FIXTURE)
            .expect("test/fixtures/vault_vectors.json exists (cargo test -- --ignored write_vectors)");
        assert_eq!(pretty(&vectors()), current, "vault_vectors.json drifted from vault.rs");
    }

    #[test]
    fn device_names_open_only_for_their_device() {
        let i = inputs();
        let k = meta_key(&i.vk);
        let device = DeviceKey::from_seed(&i.device_seed);
        let other = DeviceKey::from_seed(&seq(0x99));
        let sealed = seal_device_name(&k, &i.vault_id, &device.device_id(), "Desk", None).unwrap();
        assert_eq!(open_device_name(&k, &i.vault_id, &device.device_id(), &sealed).unwrap(), "Desk");
        assert!(open_device_name(&k, &i.vault_id, &other.device_id(), &sealed).is_err(), "bound to its device");
        assert!(seal_device_name(&k, &i.vault_id, &device.device_id(), "", None).is_err());
        assert!(seal_device_name(&k, &i.vault_id, &device.device_id(), "a\0b", None).is_err());
        assert!(seal_device_name(&k, &i.vault_id, &device.device_id(), &"x".repeat(101), None).is_err());
    }

    #[test]
    fn dedupe_tag_is_per_vault_and_per_content() {
        let i = inputs();
        let h: [u8; 32] = Sha256::digest(&i.plaintext).into();
        let k = dedupe_key(&i.vk);
        let tag = dedupe_tag(&k, &h);
        assert_eq!(from_b64u(&tag).unwrap().len(), DEDUPE_TAG_SIZE);
        assert_eq!(tag, dedupe_tag(&k, &h), "same content, same vault: same tag");
        assert_ne!(tag, dedupe_tag(&dedupe_key(&seq(0x11)), &h), "another vault: another tag");
        assert_ne!(tag, dedupe_tag(&k, &[0u8; 32]), "other content: another tag");
        assert_ne!(k, meta_key(&i.vk));
    }

    #[test]
    fn compression_round_trips_and_is_bounded() {
        let plain = compressible_plaintext();
        let z = deflate_raw(&plain);
        assert!(z.len() * 2 < plain.len(), "the vector text compresses well");
        assert_eq!(inflate_raw(&z, plain.len()).unwrap(), plain);
        // Exactly the sealed size, no more and no less.
        assert_eq!(inflate_raw(&z, plain.len() - 1), Err(VaultError::BadCompression));
        assert_eq!(inflate_raw(&z, plain.len() + 1), Err(VaultError::BadCompression));
        assert_eq!(inflate_raw(b"not deflate at all", 10), Err(VaultError::BadCompression));
        // A small stream that would expand to 10 MB stops at the limit.
        let bomb = deflate_raw(&vec![0u8; 10_000_000]);
        assert!(bomb.len() < 20_000);
        assert_eq!(inflate_raw(&bomb, 1000), Err(VaultError::BadCompression));
    }

    #[test]
    fn compression_is_sealed_in_the_metadata() {
        let i = inputs();
        let cm = compressed_meta(&i);
        let json = cm.to_json().unwrap();
        assert!(json.ends_with(r#","z":"deflate"}"#), "z is written last: {json}");
        assert_eq!(ObjectMeta::from_json(&json).unwrap(), cm);
        // Without z the file was stored as it is.
        assert!(!file_meta(&i).to_json().unwrap().contains("\"z\""));
        // An unknown z cannot be read back, so the entry is refused.
        let other = json.replace(r#""z":"deflate""#, r#""z":"zstd""#);
        assert!(matches!(ObjectMeta::from_json(&other), Err(VaultError::BadMeta(_))));
        // A folder never carries z.
        let dir = ObjectMeta { compression: Some(Compression::Deflate), ..dir_meta() };
        assert!(!dir.to_json().unwrap().contains("\"z\""));
    }

    #[test]
    fn ids_have_the_spec_shape() {
        let i = inputs();
        assert_eq!(i.vault_id, "aaaqeayeaudaocajbifqydiob4");
        assert!(is_vault_id(&i.vault_id));
        assert!(!is_vault_id("AAAQEAYEAUDAOCAJBIFQYDIOB4"));
        assert!(!is_vault_id("aaaqeayeaudaocajbifqydiob"));
        assert!(is_object_id(&i.file_id));
        assert!(!is_object_id("cHFyc3R1dnd4eXp7fH1-f"));
        assert_eq!(generate_object_id().len(), SHORT_ID_LEN);
        assert_eq!(base32_lower(b""), "");
        assert_eq!(base32_lower(b"f"), "my");
        assert_eq!(base32_lower(b"foobar"), "mzxw6ytboi");
    }

    #[test]
    fn key_check_and_meta_key_are_stable() {
        let i = inputs();
        assert_eq!(key_check(&i.vk).len(), 22);
        assert_ne!(key_check(&i.vk), key_check(&seq(0x11)));
        assert_ne!(meta_key(&i.vk), i.vk);
    }

    #[test]
    fn phrase_round_trips_and_rejects_a_bad_checksum() {
        let i = inputs();
        let phrase = phrase_from_key(&i.vk);
        assert_eq!(phrase.split(' ').count(), 24);
        assert_eq!(key_from_phrase(&phrase).unwrap(), i.vk);
        // Forgiven: case, extra whitespace, a trailing newline.
        let messy = format!("  {}\n", phrase.to_uppercase().replace(' ', "   "));
        assert_eq!(key_from_phrase(&messy).unwrap(), i.vk);
        // Not forgiven: a swapped word, a wrong count, a wrong word.
        let mut words: Vec<&str> = phrase.split(' ').collect();
        words.swap(0, 1);
        assert!(matches!(key_from_phrase(&words.join(" ")), Err(VaultError::BadPhrase)));
        assert!(matches!(key_from_phrase(&phrase.rsplit_once(' ').unwrap().0), Err(VaultError::BadPhrase)));
        assert!(matches!(key_from_phrase(&phrase.replacen(words[1], "zzzz", 1)), Err(VaultError::BadPhrase)));
        // A 12-word phrase is a valid mnemonic but not a vault key.
        let twelve = bip39::Mnemonic::from_entropy(&seq::<16>(1)).unwrap().to_string();
        assert!(matches!(key_from_phrase(&twelve), Err(VaultError::BadPhrase)));
    }

    #[test]
    fn key_copy_opens_only_with_its_half_and_vault() {
        let i = inputs();
        let blob = seal_key_copy(&i.server_half, &i.vault_id, &i.vk, None).unwrap();
        assert_eq!(blob.len(), KEY_COPY_SIZE);
        assert_eq!(open_key_copy(&i.server_half, &i.vault_id, &blob).unwrap(), i.vk);
        let other_vault = vault_id_from_bytes(&seq::<16>(0x01));
        assert_eq!(open_key_copy(&i.server_half, &other_vault, &blob), Err(VaultError::AuthFailed));
        assert_eq!(open_key_copy(&seq(0x31), &i.vault_id, &blob), Err(VaultError::AuthFailed));
        let mut flipped = blob.clone();
        flipped[40] ^= 1;
        assert_eq!(open_key_copy(&i.server_half, &i.vault_id, &flipped), Err(VaultError::AuthFailed));
        let mut magic = blob.clone();
        magic[0] = b'X';
        assert_eq!(open_key_copy(&i.server_half, &i.vault_id, &magic), Err(VaultError::BadKeyCopy));
        assert_eq!(open_key_copy(&i.server_half, &i.vault_id, &blob[..64]), Err(VaultError::BadKeyCopy));
        assert_eq!(seal_key_copy(&i.server_half, "nope", &i.vk, None), Err(VaultError::InvalidVaultId));
    }

    #[test]
    fn meta_json_is_canonical_and_validated() {
        let i = inputs();
        let fm = file_meta(&i);
        let json = fm.to_json().unwrap();
        assert!(json.starts_with(r#"{"v":1,"k":"file","n":"Résumé 📄 final.pdf","p":""#));
        assert!(json.contains(r#""m":1728000000123,"s":138,"t":"application/pdf","fk":""#));
        assert_eq!(ObjectMeta::from_json(&json).unwrap(), fm);
        // A folder writes only its own fields, with p: null at the root.
        assert_eq!(dir_meta().to_json().unwrap(), r#"{"v":1,"k":"dir","n":"Photos 2026","p":null,"m":1727000000000}"#);
        // Readers ignore unknown keys and file-only keys on a folder.
        let lenient = r#"{"v":1,"k":"dir","n":"x","p":null,"m":1,"s":5,"zzz":true}"#;
        assert_eq!(ObjectMeta::from_json(lenient).unwrap(), ObjectMeta { name: "x".into(), mtime_ms: 1, ..dir_meta() });
        for bad_json in [
            r#"{"v":2,"k":"dir","n":"x","p":null,"m":1}"#,
            r#"{"v":1,"k":"link","n":"x","p":null,"m":1}"#,
            r#"{"v":1,"k":"dir","n":"","p":null,"m":1}"#,
            r#"{"v":1,"k":"dir","n":"a/b","p":null,"m":1}"#,
            r#"{"v":1,"k":"dir","n":"x","p":"short","m":1}"#,
            r#"{"v":1,"k":"file","n":"x","p":null,"m":1,"s":1,"t":"a/b","fk":"AAAA"}"#,
            r#"{"v":1,"k":"file","n":"x","p":null,"m":1,"t":"a/b","fk":"AAAA","h":"AAAA"}"#,
            r#"{"v":1,"k":"file","n":"x","p":null,"m":1,"s":1,"t":"","fk":"AAAA","h":"AAAA"}"#,
        ] {
            assert!(matches!(ObjectMeta::from_json(bad_json), Err(VaultError::BadMeta(_))), "{bad_json}");
        }
        let mut no_hash = fm.clone();
        no_hash.hash = None;
        assert!(matches!(no_hash.to_json(), Err(VaultError::BadMeta(_))));
    }

    #[test]
    fn sealed_meta_is_bound_to_vault_and_object() {
        let i = inputs();
        let k = meta_key(&i.vk);
        let fm = file_meta(&i);
        let enc = seal_meta(&k, &i.vault_id, &i.file_id, &fm, None).unwrap();
        assert_eq!(open_meta(&k, &i.vault_id, &i.file_id, &enc).unwrap(), fm);
        assert_eq!(open_meta(&k, &i.vault_id, &i.dir_id, &enc), Err(VaultError::AuthFailed));
        let other_vault = vault_id_from_bytes(&seq::<16>(0x01));
        assert_eq!(open_meta(&k, &other_vault, &i.file_id, &enc), Err(VaultError::AuthFailed));
        assert_eq!(open_meta(&meta_key(&seq(0x11)), &i.vault_id, &i.file_id, &enc), Err(VaultError::AuthFailed));
        let mut raw = from_b64u(&enc).unwrap();
        raw[20] ^= 0x80;
        assert_eq!(open_meta(&k, &i.vault_id, &i.file_id, &b64u(&raw)), Err(VaultError::AuthFailed));
        assert_eq!(open_meta(&k, &i.vault_id, &i.file_id, "AAAA"), Err(VaultError::SealedBoxTooShort));
        assert_eq!(seal_meta(&k, "nope", &i.file_id, &fm, None), Err(VaultError::InvalidVaultId));
        assert_eq!(seal_meta(&k, &i.vault_id, "nope", &fm, None), Err(VaultError::InvalidObjectId));
    }

    #[test]
    fn thumbnail_round_trips_and_is_bound() {
        let i = inputs();
        let sealed = seal_thumbnail(&i.file_key, &i.vault_id, &i.file_id, &i.thumbnail, None).unwrap();
        assert_eq!(open_thumbnail(&i.file_key, &i.vault_id, &i.file_id, &sealed).unwrap(), i.thumbnail);
        assert_eq!(open_thumbnail(&i.file_key, &i.vault_id, &i.dir_id, &sealed), Err(VaultError::AuthFailed));
        assert_eq!(open_thumbnail(&seq(0x81), &i.vault_id, &i.file_id, &sealed), Err(VaultError::AuthFailed));
    }

    #[test]
    fn grant_hands_vk_over_and_checks_it() {
        let i = inputs();
        let new_key = GrantKey::generate();
        let granter = GrantKey::generate();
        let boxed = grant(&i.vk, &i.vault_id, &granter, &new_key.public_bytes(), None).unwrap();
        let kid = key_check(&i.vk);
        assert_eq!(accept_grant(&i.vault_id, &new_key, &granter.public_bytes(), &boxed, &kid).unwrap(), i.vk);
        // Wrong vault id, wrong key check, wrong recipient, tampered box.
        let other_vault = vault_id_from_bytes(&seq::<16>(0x01));
        assert_eq!(accept_grant(&other_vault, &new_key, &granter.public_bytes(), &boxed, &kid), Err(VaultError::AuthFailed));
        assert_eq!(
            accept_grant(&i.vault_id, &new_key, &granter.public_bytes(), &boxed, &key_check(&seq(0x11))),
            Err(VaultError::KeyCheckMismatch)
        );
        let stranger = GrantKey::generate();
        assert_eq!(accept_grant(&i.vault_id, &stranger, &granter.public_bytes(), &boxed, &kid), Err(VaultError::AuthFailed));
        let mut flipped = boxed.clone();
        flipped[15] ^= 1;
        assert_eq!(accept_grant(&i.vault_id, &new_key, &granter.public_bytes(), &flipped, &kid), Err(VaultError::AuthFailed));
        // An all-zero public key gives a non-contributory shared secret.
        assert_eq!(grant(&i.vk, &i.vault_id, &granter, &[0u8; 32], None), Err(VaultError::BadPublicKey));
    }

    #[test]
    fn requests_verify_only_as_signed() {
        let i = inputs();
        let device = DeviceKey::from_seed(&i.device_seed);
        let pk = device.public_bytes();
        assert_eq!(DeviceKey::from_seed(&device.seed()).public_bytes(), pk);
        assert_eq!(device.device_id().len(), SHORT_ID_LEN);
        assert_eq!(device.signin_nonce().len(), 43);
        let sig = device.sign_request("post", &i.req_path, i.req_ts, i.req_body);
        assert!(verify_request(&pk, "POST", &i.req_path, i.req_ts, i.req_body, &sig).is_ok());
        assert_eq!(verify_request(&pk, "GET", &i.req_path, i.req_ts, i.req_body, &sig), Err(VaultError::BadSignature));
        assert_eq!(verify_request(&pk, "POST", "/api/v1/vault/x", i.req_ts, i.req_body, &sig), Err(VaultError::BadSignature));
        assert_eq!(verify_request(&pk, "POST", &i.req_path, i.req_ts + 1, i.req_body, &sig), Err(VaultError::BadSignature));
        assert_eq!(verify_request(&pk, "POST", &i.req_path, i.req_ts, b"{}", &sig), Err(VaultError::BadSignature));
        let other = DeviceKey::from_seed(&seq(0x61)).public_bytes();
        assert_eq!(verify_request(&other, "POST", &i.req_path, i.req_ts, i.req_body, &sig), Err(VaultError::BadSignature));
        // 0x61, 0x62, … is not a point on the curve at all.
        assert_eq!(verify_request(&seq(0x61), "POST", &i.req_path, i.req_ts, i.req_body, &sig), Err(VaultError::BadPublicKey));
        assert_eq!(verify_request(&pk, "POST", &i.req_path, i.req_ts, i.req_body, "AAAA"), Err(VaultError::BadSignature));
        // An empty body hashes to the well-known SHA-256 of nothing.
        assert!(request_message("GET", "/x", 1, b"").ends_with("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"));
    }

    #[test]
    fn authorization_header_round_trips_and_rejects_junk() {
        let i = inputs();
        let device = DeviceKey::from_seed(&i.device_seed);
        let header = device.authorization(&i.vault_id, "POST", &i.req_path, i.req_ts, i.req_body).unwrap();
        let parsed = Authorization::parse(&header).unwrap();
        assert_eq!(parsed.vault_id, i.vault_id);
        assert_eq!(parsed.device_id, device.device_id());
        assert_eq!(parsed.ts, i.req_ts);
        assert!(verify_request(&device.public_bytes(), "POST", &i.req_path, parsed.ts, i.req_body, &parsed.signature).is_ok());
        assert_eq!(parsed.header(), header);
        for junk in [
            "",
            "Bearer abc",
            "BIShare-Vault",
            "BIShare-Vault v=2,vault=aaaqeayeaudaocajbifqydiob4,device=cHFyc3R1dnd4eXp7fH1-fw,ts=1,sig=AAAA",
            &header.replace("v=1,", ""),
            &header.replace("ts=", "ts=x"),
            &format!("{header},extra=1"),
            &format!("{header},v=1"),
            &header.replace(&i.vault_id, "AAAQ"),
        ] {
            assert_eq!(Authorization::parse(junk), Err(VaultError::BadAuthorization), "{junk}");
        }
        assert_eq!(device.authorization("nope", "GET", "/", 0, b""), Err(VaultError::InvalidVaultId));
    }
}
