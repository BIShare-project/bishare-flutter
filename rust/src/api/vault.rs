//! Vault (BIShare Drive) keys, envelopes and signatures —
//! `bishare_protocol::vault`, the canonical implementation of VAULT-SPEC.md,
//! exposed to Dart. Every call is synchronous and small; the file bytes
//! themselves go through the BSE2 functions in `bse2.rs` with the file key
//! these functions hand out.
//!
//! Nonces are always random here. The Rust tests pin the sealed bytes with
//! fixed nonces; Dart proves the bridge by opening those vectors and by
//! round-tripping what it seals.

use bishare_protocol::vault as v;

fn key32(bytes: &[u8], what: &str) -> Result<[u8; 32], String> {
    bytes
        .try_into()
        .map_err(|_| format!("{what} must be 32 bytes"))
}

fn err(e: v::VaultError) -> String {
    e.to_string()
}

/// What is sealed about one file or folder. `kind` is "file" or "dir"; the
/// last four fields apply to files only.
pub struct VaultMeta {
    pub kind: String,
    pub name: String,
    pub parent: Option<String>,
    pub mtime_ms: i64,
    pub size: Option<i64>,
    pub mime: Option<String>,
    pub file_key: Option<Vec<u8>>,
    pub hash: Option<Vec<u8>>,
}

impl VaultMeta {
    fn into_meta(self) -> Result<v::ObjectMeta, String> {
        let kind = match self.kind.as_str() {
            "file" => v::ObjectKind::File,
            "dir" => v::ObjectKind::Dir,
            other => return Err(format!("unknown kind {other:?}")),
        };
        let size = match self.size {
            Some(s) if s < 0 => return Err("size must not be negative".into()),
            Some(s) => Some(s as u64),
            None => None,
        };
        Ok(v::ObjectMeta {
            kind,
            name: self.name,
            parent: self.parent,
            mtime_ms: self.mtime_ms,
            size,
            mime: self.mime,
            file_key: self.file_key.as_deref().map(|k| key32(k, "file key")).transpose()?,
            hash: self.hash.as_deref().map(|h| key32(h, "hash")).transpose()?,
        })
    }

    fn from_meta(m: v::ObjectMeta) -> Self {
        Self {
            kind: match m.kind {
                v::ObjectKind::File => "file".into(),
                v::ObjectKind::Dir => "dir".into(),
            },
            name: m.name,
            parent: m.parent,
            mtime_ms: m.mtime_ms,
            size: m.size.map(|s| s as i64),
            mime: m.mime,
            file_key: m.file_key.map(|k| k.to_vec()),
            hash: m.hash.map(|h| h.to_vec()),
        }
    }
}

// ── ids and keys ────────────────────────────────────────────────────────────

#[flutter_rust_bridge::frb(sync)]
pub fn vault_generate_key() -> Vec<u8> {
    v::generate_vault_key().to_vec()
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_generate_file_key() -> Vec<u8> {
    v::generate_file_key().to_vec()
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_generate_object_id() -> String {
    v::generate_object_id()
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_is_vault_id(id: String) -> bool {
    v::is_vault_id(&id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_is_object_id(id: String) -> bool {
    v::is_object_id(&id)
}

/// The key check the server keeps; a received vault key is compared to it.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_key_check(vault_key: Vec<u8>) -> Result<String, String> {
    Ok(v::key_check(&key32(&vault_key, "vault key")?))
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_meta_key(vault_key: Vec<u8>) -> Result<Vec<u8>, String> {
    Ok(v::meta_key(&key32(&vault_key, "vault key")?).to_vec())
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_thumb_key(file_key: Vec<u8>) -> Result<Vec<u8>, String> {
    Ok(v::thumb_key(&key32(&file_key, "file key")?).to_vec())
}

/// The 24-word recovery phrase of a vault key.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_phrase_from_key(vault_key: Vec<u8>) -> Result<String, String> {
    Ok(v::phrase_from_key(&key32(&vault_key, "vault key")?))
}

/// The vault key from a phrase as typed; case and spacing are forgiven, a
/// wrong word or checksum is not.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_key_from_phrase(phrase: String) -> Result<Vec<u8>, String> {
    v::key_from_phrase(&phrase).map(|k| k.to_vec()).map_err(err)
}

// ── key copy ────────────────────────────────────────────────────────────────

/// The 65-byte copy of the vault key kept in the person's own account.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_seal_key_copy(
    server_half: Vec<u8>,
    vault_id: String,
    vault_key: Vec<u8>,
) -> Result<Vec<u8>, String> {
    v::seal_key_copy(
        &key32(&server_half, "server half")?,
        &vault_id,
        &key32(&vault_key, "vault key")?,
        None,
    )
    .map_err(err)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_open_key_copy(
    server_half: Vec<u8>,
    vault_id: String,
    key_copy: Vec<u8>,
) -> Result<Vec<u8>, String> {
    v::open_key_copy(&key32(&server_half, "server half")?, &vault_id, &key_copy)
        .map(|k| k.to_vec())
        .map_err(err)
}

// ── metadata and thumbnails ─────────────────────────────────────────────────

#[flutter_rust_bridge::frb(sync)]
pub fn vault_seal_meta(
    meta_key: Vec<u8>,
    vault_id: String,
    object_id: String,
    meta: VaultMeta,
) -> Result<String, String> {
    v::seal_meta(
        &key32(&meta_key, "meta key")?,
        &vault_id,
        &object_id,
        &meta.into_meta()?,
        None,
    )
    .map_err(err)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_open_meta(
    meta_key: Vec<u8>,
    vault_id: String,
    object_id: String,
    enc_meta: String,
) -> Result<VaultMeta, String> {
    v::open_meta(&key32(&meta_key, "meta key")?, &vault_id, &object_id, &enc_meta)
        .map(VaultMeta::from_meta)
        .map_err(err)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_seal_thumbnail(
    file_key: Vec<u8>,
    vault_id: String,
    object_id: String,
    jpeg: Vec<u8>,
) -> Result<Vec<u8>, String> {
    v::seal_thumbnail(&key32(&file_key, "file key")?, &vault_id, &object_id, &jpeg, None)
        .map_err(err)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_open_thumbnail(
    file_key: Vec<u8>,
    vault_id: String,
    object_id: String,
    sealed: Vec<u8>,
) -> Result<Vec<u8>, String> {
    v::open_thumbnail(&key32(&file_key, "file key")?, &vault_id, &object_id, &sealed)
        .map_err(err)
}

// ── the grant ───────────────────────────────────────────────────────────────

/// A one-off X25519 key pair for handing the vault key to another device.
pub struct VaultGrantKey {
    pub secret: Vec<u8>,
    pub public: Vec<u8>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_grant_key_generate() -> VaultGrantKey {
    let k = v::GrantKey::generate();
    VaultGrantKey {
        secret: k.secret_bytes().to_vec(),
        public: k.public_bytes().to_vec(),
    }
}

/// Seal the vault key for the device whose public key was read from its QR
/// code. The caller sends the box together with `mine`'s public key.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_grant(
    vault_key: Vec<u8>,
    vault_id: String,
    mine_secret: Vec<u8>,
    new_pub: Vec<u8>,
) -> Result<Vec<u8>, String> {
    let mine = v::GrantKey::from_bytes(&key32(&mine_secret, "grant secret")?);
    v::grant(
        &key32(&vault_key, "vault key")?,
        &vault_id,
        &mine,
        &key32(&new_pub, "public key")?,
        None,
    )
    .map_err(err)
}

/// Open a grant and keep the vault key only if it matches the server's key
/// check.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_accept_grant(
    vault_id: String,
    mine_secret: Vec<u8>,
    granter_pub: Vec<u8>,
    boxed: Vec<u8>,
    expected_key_check: String,
) -> Result<Vec<u8>, String> {
    let mine = v::GrantKey::from_bytes(&key32(&mine_secret, "grant secret")?);
    v::accept_grant(
        &vault_id,
        &mine,
        &key32(&granter_pub, "public key")?,
        &boxed,
        &expected_key_check,
    )
    .map(|k| k.to_vec())
    .map_err(err)
}

// ── device key and signed requests ──────────────────────────────────────────

/// A new device key: the 32-byte seed to keep in secure storage.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_device_key_generate() -> Vec<u8> {
    v::DeviceKey::generate().seed().to_vec()
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_device_public_key(seed: Vec<u8>) -> Result<Vec<u8>, String> {
    Ok(v::DeviceKey::from_seed(&key32(&seed, "device seed")?).public_bytes().to_vec())
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_device_id(public_key: Vec<u8>) -> Result<String, String> {
    Ok(v::device_id_of(&key32(&public_key, "public key")?))
}

/// The nonce to put into the Apple or Google sign-in request.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_signin_nonce(public_key: Vec<u8>) -> Result<String, String> {
    Ok(v::signin_nonce(&key32(&public_key, "public key")?))
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_request_message(
    method: String,
    path_and_query: String,
    ts: i64,
    body: Vec<u8>,
) -> String {
    v::request_message(&method, &path_and_query, ts, &body)
}

#[flutter_rust_bridge::frb(sync)]
pub fn vault_sign_request(
    seed: Vec<u8>,
    method: String,
    path_and_query: String,
    ts: i64,
    body: Vec<u8>,
) -> Result<String, String> {
    Ok(v::DeviceKey::from_seed(&key32(&seed, "device seed")?)
        .sign_request(&method, &path_and_query, ts, &body))
}

/// The complete `Authorization` header value for one request.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_authorization(
    seed: Vec<u8>,
    vault_id: String,
    method: String,
    path_and_query: String,
    ts: i64,
    body: Vec<u8>,
) -> Result<String, String> {
    v::DeviceKey::from_seed(&key32(&seed, "device seed")?)
        .authorization(&vault_id, &method, &path_and_query, ts, &body)
        .map_err(err)
}

/// What the server does with a request; here so a test can prove the bridge
/// signs the same bytes.
#[flutter_rust_bridge::frb(sync)]
pub fn vault_verify_request(
    public_key: Vec<u8>,
    method: String,
    path_and_query: String,
    ts: i64,
    body: Vec<u8>,
    signature: String,
) -> Result<(), String> {
    v::verify_request(
        &key32(&public_key, "public key")?,
        &method,
        &path_and_query,
        ts,
        &body,
        &signature,
    )
    .map_err(err)
}
