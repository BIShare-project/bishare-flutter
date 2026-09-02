//! BSE2 — the end-to-end-encrypted cloud-link container
//! (`bishare_protocol::bse2`), exposed to Dart as whole-file operations so the
//! app's Remote Share uploads ciphertext exactly like the web client does, and
//! decrypts web uploads with the same shared code. Crypto runs in Rust (hardware
//! AES where the platform has it), never on the Dart event loop.

use std::fs::{self, File};
use std::io::{BufReader, BufWriter};

use bishare_protocol::bse2;

use crate::frb_generated::StreamSink;

/// Progress of a whole-file seal/open: plaintext bytes done out of total.
pub struct Bse2Progress {
    pub done: u64,
    pub total: u64,
}

/// Fresh random 32-byte AES-256 key for one transfer.
#[flutter_rust_bridge::frb(sync)]
pub fn bse2_generate_key() -> Vec<u8> {
    bse2::generate_key().to_vec()
}

/// URL-safe base64 (no padding) — the text after `#k=` in a share link.
#[flutter_rust_bridge::frb(sync)]
pub fn bse2_encode_key(key: Vec<u8>) -> Option<String> {
    let k: [u8; bse2::KEY_SIZE] = key.try_into().ok()?;
    Some(bse2::encode_key(&k))
}

/// Inverse of [`bse2_encode_key`]; `None` unless it decodes to 32 bytes.
#[flutter_rust_bridge::frb(sync)]
pub fn bse2_decode_key(fragment: String) -> Option<Vec<u8>> {
    bse2::decode_key(&fragment).map(|k| k.to_vec())
}

/// Exact container length for a plaintext of this size — what the uploader
/// must reserve, since the relay only ever sees ciphertext.
#[flutter_rust_bridge::frb(sync)]
pub fn bse2_ciphertext_size(plaintext_size: u64) -> u64 {
    bse2::ciphertext_size(plaintext_size)
}

/// True when `head` (the first bytes of a file) carries the container magic.
#[flutter_rust_bridge::frb(sync)]
pub fn bse2_is_container(head: Vec<u8>) -> bool {
    bse2::is_container(&head)
}

/// Seal the file at `input_path` into a new container at `output_path` with a
/// fresh random salt. Runs on its own thread and returns at once; progress
/// streams through `sink`, and the stream closing without an error means the
/// output is complete and synced to disk. A failure is delivered INTO the
/// sink via `add_error` (FRB sink-fn rule — see `quic_send_file`), and the
/// partial output file is removed so a caller can never upload a stub.
pub fn bse2_encrypt_file(
    sink: StreamSink<Bse2Progress>,
    input_path: String,
    output_path: String,
    key: Vec<u8>,
) {
    std::thread::spawn(move || {
        if let Err(e) = encrypt_inner(&sink, &input_path, &output_path, &key) {
            let _ = fs::remove_file(&output_path);
            let _ = sink.add_error(e);
        }
    });
}

fn encrypt_inner(
    sink: &StreamSink<Bse2Progress>,
    input_path: &str,
    output_path: &str,
    key: &[u8],
) -> Result<(), String> {
    let k: [u8; bse2::KEY_SIZE] = key
        .try_into()
        .map_err(|_| bse2::Bse2Error::InvalidKey.to_string())?;
    let input = File::open(input_path).map_err(|e| format!("open input: {e}"))?;
    let total = input
        .metadata()
        .map_err(|e| format!("stat input: {e}"))?
        .len();
    let output = File::create(output_path).map_err(|e| format!("create output: {e}"))?;
    let mut writer = BufWriter::new(output);
    bse2::encrypt(
        BufReader::new(input),
        &mut writer,
        &k,
        bse2::generate_salt(),
        bse2::RECORD_SIZE,
        total,
        |done| {
            let _ = sink.add(Bse2Progress { done, total });
        },
    )
    .map_err(|e| e.to_string())?;
    // Everything on disk before Dart opens the file for upload.
    writer
        .into_inner()
        .map_err(|e| format!("flush output: {e}"))?
        .sync_all()
        .map_err(|e| format!("sync output: {e}"))?;
    Ok(())
}

/// Open the container at `input_path` into the plaintext file at
/// `output_path`. Same threading/error contract as [`bse2_encrypt_file`]; on
/// any failure (wrong key, tampering, truncation) the partial output is
/// removed — the caller never sees half a file reported as success.
pub fn bse2_decrypt_file(
    sink: StreamSink<Bse2Progress>,
    input_path: String,
    output_path: String,
    key: Vec<u8>,
) {
    std::thread::spawn(move || {
        if let Err(e) = decrypt_inner(&sink, &input_path, &output_path, &key) {
            let _ = fs::remove_file(&output_path);
            let _ = sink.add_error(e);
        }
    });
}

fn decrypt_inner(
    sink: &StreamSink<Bse2Progress>,
    input_path: &str,
    output_path: &str,
    key: &[u8],
) -> Result<(), String> {
    let k: [u8; bse2::KEY_SIZE] = key
        .try_into()
        .map_err(|_| bse2::Bse2Error::InvalidKey.to_string())?;
    let input = File::open(input_path).map_err(|e| format!("open input: {e}"))?;
    let output = File::create(output_path).map_err(|e| format!("create output: {e}"))?;
    let mut writer = BufWriter::new(output);
    bse2::decrypt(BufReader::new(input), &mut writer, &k, |done, total| {
        let _ = sink.add(Bse2Progress { done, total });
    })
    .map_err(|e| e.to_string())?;
    writer
        .into_inner()
        .map_err(|e| format!("flush output: {e}"))?
        .sync_all()
        .map_err(|e| format!("sync output: {e}"))?;
    Ok(())
}
