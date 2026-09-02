//! BSE2 — the end-to-end-encrypted container used for cloud transfer links.
//!
//! This module is the **canonical specification**. The web client
//! (`bishare-web/src/lib/e2e/crypto.ts`) is a byte-compatible WebCrypto
//! implementation of the same format; the golden vectors in the tests below
//! were produced by that implementation, so a change that breaks either side
//! fails here.
//!
//! Container format ("BSE2" v1):
//!
//! ```text
//! header (24 bytes):
//!   [0..4)   magic  = "BSE2"
//!   [4]      version = 1
//!   [5..8)   reserved (0)
//!   [8..12)  salt (4 random bytes per file — folded into every nonce)
//!   [12..16) recordSize (u32 BE, plaintext bytes per record)
//!   [16..24) plaintextSize (u64 BE)
//! then back-to-back records; record i:
//!   AES-256-GCM(plaintext[i*RS ..], iv = salt ‖ u64BE(i), aad = u32BE(i))
//!   = ciphertext (plaintext length) ‖ 16-byte tag
//! ```
//!
//! Putting the record index in both the nonce and the AAD makes every nonce
//! unique under a key and pins each record to its position, so a reordered,
//! duplicated or removed record fails authentication. `plaintextSize` in the
//! header pins the total, so truncation is detected before success is claimed.
//! Because nonce and AAD derive from the *index* rather than from running
//! stream state, any record decrypts on its own — the property the web
//! streaming player relies on for Range requests.
//!
//! A zero-byte file is one empty record (a lone 16-byte tag), never zero
//! records — so an empty upload is still authenticated.

use std::fmt;
use std::io::{self, Read, Write};

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use rand::RngCore;

pub const MAGIC: [u8; 4] = *b"BSE2";
pub const VERSION: u8 = 1;
pub const HEADER_SIZE: usize = 24;
pub const TAG_SIZE: usize = 16;
pub const KEY_SIZE: usize = 32;
pub const SALT_SIZE: usize = 4;
pub const NONCE_SIZE: usize = 12;
/// Plaintext bytes per record. Every production writer uses this value.
pub const RECORD_SIZE: u32 = 1024 * 1024;
/// Largest record size a reader accepts from a header — guards a hostile
/// header from asking us to buffer gigabytes (mirrors the Dart/web readers).
pub const MAX_RECORD_SIZE: u32 = 64 * 1024 * 1024;

#[derive(Debug)]
pub enum Bse2Error {
    TruncatedHeader,
    NotEncrypted,
    UnsupportedVersion(u8),
    InvalidRecordSize(u32),
    InvalidKey,
    /// Ciphertext ended before the record count promised by the header.
    TruncatedStream,
    /// GCM tag mismatch: wrong key, tampered, reordered or corrupted record.
    AuthFailed,
    /// Bytes remain after the last record.
    TrailingData,
    /// The plaintext source did not provide the byte count the header claims
    /// (the file changed size while it was being encrypted).
    SizeMismatch {
        expected: u64,
        actual: u64,
    },
    Io(io::Error),
}

impl fmt::Display for Bse2Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::TruncatedHeader => write!(f, "truncated header"),
            Self::NotEncrypted => write!(f, "not an encrypted file"),
            Self::UnsupportedVersion(v) => write!(f, "unsupported version {v}"),
            Self::InvalidRecordSize(rs) => write!(f, "invalid record size {rs}"),
            Self::InvalidKey => write!(f, "key must be {KEY_SIZE} bytes"),
            Self::TruncatedStream => write!(f, "truncated stream"),
            Self::AuthFailed => write!(f, "decryption failed — wrong key or corrupted file"),
            Self::TrailingData => write!(f, "unexpected trailing data"),
            Self::SizeMismatch { expected, actual } => {
                write!(
                    f,
                    "plaintext size changed during encryption (expected {expected}, got {actual})"
                )
            }
            Self::Io(e) => write!(f, "io error: {e}"),
        }
    }
}

impl std::error::Error for Bse2Error {}

impl From<io::Error> for Bse2Error {
    fn from(e: io::Error) -> Self {
        Self::Io(e)
    }
}

/// The parsed 24-byte header.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Header {
    pub salt: [u8; SALT_SIZE],
    pub record_size: u32,
    pub plaintext_size: u64,
}

impl Header {
    pub fn encode(&self) -> [u8; HEADER_SIZE] {
        let mut h = [0u8; HEADER_SIZE];
        h[0..4].copy_from_slice(&MAGIC);
        h[4] = VERSION;
        h[8..12].copy_from_slice(&self.salt);
        h[12..16].copy_from_slice(&self.record_size.to_be_bytes());
        h[16..24].copy_from_slice(&self.plaintext_size.to_be_bytes());
        h
    }

    /// Parse and validate. Rejects foreign bytes, other versions and record
    /// sizes outside `1..=MAX_RECORD_SIZE`.
    pub fn parse(bytes: &[u8]) -> Result<Header, Bse2Error> {
        if bytes.len() < HEADER_SIZE {
            return Err(Bse2Error::TruncatedHeader);
        }
        if bytes[0..4] != MAGIC {
            return Err(Bse2Error::NotEncrypted);
        }
        if bytes[4] != VERSION {
            return Err(Bse2Error::UnsupportedVersion(bytes[4]));
        }
        let mut salt = [0u8; SALT_SIZE];
        salt.copy_from_slice(&bytes[8..12]);
        let record_size = u32::from_be_bytes(bytes[12..16].try_into().expect("4 bytes"));
        if record_size == 0 || record_size > MAX_RECORD_SIZE {
            return Err(Bse2Error::InvalidRecordSize(record_size));
        }
        let plaintext_size = u64::from_be_bytes(bytes[16..24].try_into().expect("8 bytes"));
        Ok(Header {
            salt,
            record_size,
            plaintext_size,
        })
    }

    pub fn record_count(&self) -> u64 {
        record_count(self.plaintext_size, self.record_size)
    }

    /// Plaintext length of record `i` (only the last one can be short).
    pub fn record_plain_len(&self, i: u64) -> u64 {
        if self.plaintext_size == 0 {
            return 0;
        }
        let start = i * u64::from(self.record_size);
        (self.plaintext_size - start).min(u64::from(self.record_size))
    }

    pub fn ciphertext_size(&self) -> u64 {
        ciphertext_size_with(self.plaintext_size, self.record_size)
    }
}

/// Number of records for a plaintext: `max(1, ceil(size / record_size))`.
pub fn record_count(plaintext_size: u64, record_size: u32) -> u64 {
    if plaintext_size == 0 {
        1
    } else {
        plaintext_size.div_ceil(u64::from(record_size))
    }
}

/// Exact container length for a plaintext of `plaintext_size` bytes with the
/// production record size. The uploader reserves storage by THIS number.
pub fn ciphertext_size(plaintext_size: u64) -> u64 {
    ciphertext_size_with(plaintext_size, RECORD_SIZE)
}

pub fn ciphertext_size_with(plaintext_size: u64, record_size: u32) -> u64 {
    HEADER_SIZE as u64
        + plaintext_size
        + record_count(plaintext_size, record_size) * TAG_SIZE as u64
}

/// iv = salt(4) ‖ u64BE(record index).
pub fn nonce_for(salt: &[u8; SALT_SIZE], index: u64) -> [u8; NONCE_SIZE] {
    let mut iv = [0u8; NONCE_SIZE];
    iv[..SALT_SIZE].copy_from_slice(salt);
    iv[SALT_SIZE..].copy_from_slice(&index.to_be_bytes());
    iv
}

/// aad = u32BE(record index).
pub fn aad_for(index: u64) -> [u8; 4] {
    (index as u32).to_be_bytes()
}

/// True when `head` begins with the container magic.
pub fn is_container(head: &[u8]) -> bool {
    head.len() >= MAGIC.len() && head[..MAGIC.len()] == MAGIC
}

pub fn generate_key() -> [u8; KEY_SIZE] {
    let mut k = [0u8; KEY_SIZE];
    rand::rngs::OsRng.fill_bytes(&mut k);
    k
}

pub fn generate_salt() -> [u8; SALT_SIZE] {
    let mut s = [0u8; SALT_SIZE];
    rand::rngs::OsRng.fill_bytes(&mut s);
    s
}

/// URL-safe base64 without padding — the exact text that follows `#k=` in a
/// share link.
pub fn encode_key(key: &[u8; KEY_SIZE]) -> String {
    URL_SAFE_NO_PAD.encode(key)
}

/// Inverse of [`encode_key`]. Tolerates padding and the standard alphabet
/// (`+`/`/`), like the web and Dart readers do; rejects anything that is not
/// exactly 32 bytes.
pub fn decode_key(fragment: &str) -> Option<[u8; KEY_SIZE]> {
    let normalized: String = fragment
        .trim()
        .trim_end_matches('=')
        .chars()
        .map(|c| match c {
            '+' => '-',
            '/' => '_',
            c => c,
        })
        .collect();
    let bytes = URL_SAFE_NO_PAD.decode(normalized).ok()?;
    bytes.try_into().ok()
}

fn cipher(key: &[u8; KEY_SIZE]) -> Aes256Gcm {
    Aes256Gcm::new_from_slice(key).expect("32-byte key")
}

/// `read_exact` that reports a clean end-of-input as `on_eof` instead of an
/// io error, and keeps going through `Interrupted`.
fn read_full<R: Read>(r: &mut R, buf: &mut [u8], on_eof: Bse2Error) -> Result<(), Bse2Error> {
    let mut filled = 0;
    while filled < buf.len() {
        match r.read(&mut buf[filled..]) {
            Ok(0) => return Err(on_eof),
            Ok(n) => filled += n,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.into()),
        }
    }
    Ok(())
}

/// Encrypt exactly `plaintext_size` bytes from `input` into `output` as a
/// BSE2 container. `on_progress` receives plaintext bytes consumed so far.
/// Returns the number of ciphertext bytes written, which always equals
/// [`ciphertext_size_with`]`(plaintext_size, record_size)`.
///
/// Deterministic in `(key, salt, plaintext)`: the same inputs produce the same
/// bytes, which is what makes the golden vectors possible. Callers MUST use a
/// fresh random salt per file (see [`generate_salt`]) — a `(key, salt)` pair
/// must never encrypt two different plaintexts.
pub fn encrypt<R: Read, W: Write>(
    mut input: R,
    mut output: W,
    key: &[u8; KEY_SIZE],
    salt: [u8; SALT_SIZE],
    record_size: u32,
    plaintext_size: u64,
    mut on_progress: impl FnMut(u64),
) -> Result<u64, Bse2Error> {
    if record_size == 0 || record_size > MAX_RECORD_SIZE {
        return Err(Bse2Error::InvalidRecordSize(record_size));
    }
    let header = Header {
        salt,
        record_size,
        plaintext_size,
    };
    output.write_all(&header.encode())?;
    let mut written = HEADER_SIZE as u64;

    let aes = cipher(key);
    let mut buf = vec![0u8; record_size as usize];
    let mut consumed = 0u64;
    for i in 0..header.record_count() {
        let plain_len = header.record_plain_len(i) as usize;
        read_full(
            &mut input,
            &mut buf[..plain_len],
            Bse2Error::SizeMismatch {
                expected: plaintext_size,
                actual: consumed,
            },
        )?;
        let nonce = nonce_for(&salt, i);
        let aad = aad_for(i);
        let ct = aes
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: &buf[..plain_len],
                    aad: &aad,
                },
            )
            .map_err(|_| Bse2Error::AuthFailed)?;
        output.write_all(&ct)?;
        written += ct.len() as u64;
        consumed += plain_len as u64;
        on_progress(consumed);
    }
    output.flush()?;
    Ok(written)
}

/// Decrypt a BSE2 container from `input` into `output`. `on_progress`
/// receives `(plaintext bytes produced, plaintext total)`. Returns the
/// plaintext length. Fails closed: any tag mismatch, truncation, trailing
/// bytes or bad header is an error, never partial silent output being
/// reported as success.
pub fn decrypt<R: Read, W: Write>(
    mut input: R,
    mut output: W,
    key: &[u8; KEY_SIZE],
    mut on_progress: impl FnMut(u64, u64),
) -> Result<u64, Bse2Error> {
    let mut head = [0u8; HEADER_SIZE];
    read_full(&mut input, &mut head, Bse2Error::TruncatedHeader)?;
    let header = Header::parse(&head)?;

    let aes = cipher(key);
    let mut buf = vec![0u8; header.record_size as usize + TAG_SIZE];
    let mut produced = 0u64;
    for i in 0..header.record_count() {
        let plain_len = header.record_plain_len(i) as usize;
        let rec = &mut buf[..plain_len + TAG_SIZE];
        read_full(&mut input, rec, Bse2Error::TruncatedStream)?;
        let nonce = nonce_for(&header.salt, i);
        let aad = aad_for(i);
        let plain = aes
            .decrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: rec,
                    aad: &aad,
                },
            )
            .map_err(|_| Bse2Error::AuthFailed)?;
        output.write_all(&plain)?;
        produced += plain.len() as u64;
        on_progress(produced, header.plaintext_size);
    }

    // The container must end exactly after the last record.
    let mut probe = [0u8; 1];
    loop {
        match input.read(&mut probe) {
            Ok(0) => break,
            Ok(_) => return Err(Bse2Error::TrailingData),
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.into()),
        }
    }
    output.flush()?;
    Ok(produced)
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD;
    use pretty_assertions::assert_eq;

    // Golden vectors produced by Node's WebCrypto running the web writer
    // (bishare-web/src/lib/e2e/crypto.ts) with key = 0x00..0x1f,
    // salt = A1B2C3D4 and recordSize = 8. The Dart test suite
    // (test/bse2_test.dart) uses the same bytes, so all three
    // implementations are pinned to one another.
    const KEY_FRAGMENT: &str = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
    const SALT: [u8; 4] = [0xA1, 0xB2, 0xC3, 0xD4];
    const PLAIN: &[u8] = b"The quick brown fox jumps!";
    const MULTI_B64: &str = "QlNFMgEAAAChssPUAAAACAAAAAAAAAAa1mtQyO3rqmeiAXEZgDE7EnMiYBVGGkF2NA8jGNbpQ6x/9nTzaFO8i7nMPGvEF6atAMJfd+Fp7FyNwM3W5fD7Mw9x5zYhFA+FgvfRC8ClvO3Ft58XeCJoLCw8";
    const EMPTY_B64: &str = "QlNFMgEAAAChssPUAAAACAAAAAAAAAAALgShd/zjx6QiLb9T2+CZBQ==";

    fn key() -> [u8; 32] {
        let mut k = [0u8; 32];
        for (i, b) in k.iter_mut().enumerate() {
            *b = i as u8;
        }
        k
    }

    fn vector(b64: &str) -> Vec<u8> {
        STANDARD.decode(b64).expect("valid vector")
    }

    fn enc(plain: &[u8], rs: u32) -> Vec<u8> {
        let mut out = Vec::new();
        let n = encrypt(
            plain,
            &mut out,
            &key(),
            SALT,
            rs,
            plain.len() as u64,
            |_| {},
        )
        .unwrap();
        assert_eq!(n, out.len() as u64);
        out
    }

    fn dec(ct: &[u8], k: &[u8; 32]) -> Result<Vec<u8>, Bse2Error> {
        let mut out = Vec::new();
        decrypt(ct, &mut out, k, |_, _| {})?;
        Ok(out)
    }

    #[test]
    fn key_fragment_decodes_to_the_vector_key() {
        assert_eq!(decode_key(KEY_FRAGMENT), Some(key()));
        assert_eq!(encode_key(&key()), KEY_FRAGMENT);
        // Tolerates padding and the standard alphabet; rejects wrong lengths.
        assert_eq!(decode_key(&format!("{KEY_FRAGMENT}=")), Some(key()));
        assert_eq!(decode_key("AAEC"), None);
        assert_eq!(decode_key("!!not-base64!!"), None);
    }

    #[test]
    fn encrypt_reproduces_the_webcrypto_vector_byte_for_byte() {
        assert_eq!(enc(PLAIN, 8), vector(MULTI_B64));
        assert_eq!(enc(b"", 8), vector(EMPTY_B64));
    }

    #[test]
    fn decrypt_reads_the_webcrypto_vector() {
        let mut out = Vec::new();
        let mut last = (0, 0);
        let n = decrypt(vector(MULTI_B64).as_slice(), &mut out, &key(), |d, t| {
            last = (d, t)
        })
        .unwrap();
        assert_eq!(out, PLAIN);
        assert_eq!(n, 26);
        assert_eq!(last, (26, 26));
        assert_eq!(dec(&vector(EMPTY_B64), &key()).unwrap(), b"");
    }

    #[test]
    fn size_math_matches_reality() {
        for (plain, rs) in [
            (0u64, 8u32),
            (1, 8),
            (8, 8),
            (9, 8),
            (26, 8),
            (0, RECORD_SIZE),
            (RECORD_SIZE as u64 * 2 + 1, RECORD_SIZE),
        ] {
            let data = vec![7u8; plain as usize];
            assert_eq!(
                enc(&data, rs).len() as u64,
                ciphertext_size_with(plain, rs),
                "plain={plain} rs={rs}"
            );
        }
        assert_eq!(ciphertext_size(0), 40);
        assert_eq!(record_count(0, 8), 1);
        assert_eq!(record_count(8, 8), 1);
        assert_eq!(record_count(9, 8), 2);
    }

    #[test]
    fn round_trip_with_production_record_size() {
        let mut data = vec![0u8; RECORD_SIZE as usize * 2 + RECORD_SIZE as usize / 2 + 1];
        rand::rngs::OsRng.fill_bytes(&mut data);
        let k = generate_key();
        let salt = generate_salt();
        let mut ct = Vec::new();
        let mut steps = Vec::new();
        encrypt(
            data.as_slice(),
            &mut ct,
            &k,
            salt,
            RECORD_SIZE,
            data.len() as u64,
            |d| steps.push(d),
        )
        .unwrap();
        assert_eq!(
            steps,
            vec![
                RECORD_SIZE as u64,
                RECORD_SIZE as u64 * 2,
                data.len() as u64
            ]
        );
        assert!(is_container(&ct));
        assert_eq!(
            Header::parse(&ct).unwrap().plaintext_size,
            data.len() as u64
        );
        assert_eq!(dec(&ct, &k).unwrap(), data);
    }

    #[test]
    fn wrong_key_fails_authentication() {
        assert!(matches!(
            dec(&vector(MULTI_B64), &[0x42; 32]),
            Err(Bse2Error::AuthFailed)
        ));
    }

    #[test]
    fn tampering_is_detected() {
        let good = vector(MULTI_B64);
        // Flip one ciphertext byte.
        let mut flipped = good.clone();
        flipped[HEADER_SIZE + 3] ^= 0x01;
        assert!(matches!(dec(&flipped, &key()), Err(Bse2Error::AuthFailed)));
        // Swap two full records: each still authenticates alone, but its
        // index-bound nonce/AAD pins it to its position.
        let rec = 8 + TAG_SIZE;
        let mut swapped = good.clone();
        let (a, b) = (HEADER_SIZE, HEADER_SIZE + rec);
        let first = swapped[a..a + rec].to_vec();
        let second = swapped[b..b + rec].to_vec();
        swapped[a..a + rec].copy_from_slice(&second);
        swapped[b..b + rec].copy_from_slice(&first);
        assert!(matches!(dec(&swapped, &key()), Err(Bse2Error::AuthFailed)));
    }

    #[test]
    fn truncation_and_trailing_bytes_are_detected() {
        let good = vector(MULTI_B64);
        assert!(matches!(
            dec(&good[..good.len() - 5], &key()),
            Err(Bse2Error::TruncatedStream)
        ));
        assert!(matches!(
            dec(&good[..10], &key()),
            Err(Bse2Error::TruncatedHeader)
        ));
        let mut trailing = good.clone();
        trailing.push(0);
        assert!(matches!(
            dec(&trailing, &key()),
            Err(Bse2Error::TrailingData)
        ));
    }

    #[test]
    fn bad_headers_are_rejected() {
        let good = vector(MULTI_B64);
        let mut magic = good.clone();
        magic[0] = b'X';
        assert!(matches!(dec(&magic, &key()), Err(Bse2Error::NotEncrypted)));
        let mut version = good.clone();
        version[4] = 2;
        assert!(matches!(
            dec(&version, &key()),
            Err(Bse2Error::UnsupportedVersion(2))
        ));
        let mut zero_rs = good.clone();
        zero_rs[12..16].copy_from_slice(&0u32.to_be_bytes());
        assert!(matches!(
            dec(&zero_rs, &key()),
            Err(Bse2Error::InvalidRecordSize(0))
        ));
        let mut huge_rs = good;
        huge_rs[12..16].copy_from_slice(&(MAX_RECORD_SIZE + 1).to_be_bytes());
        assert!(matches!(
            dec(&huge_rs, &key()),
            Err(Bse2Error::InvalidRecordSize(_))
        ));
        assert!(!is_container(b"PK\x03\x04"));
    }

    #[test]
    fn a_source_that_shrinks_is_an_error_not_a_short_container() {
        let mut out = Vec::new();
        let r = encrypt(&b"hello"[..], &mut out, &key(), SALT, 8, 10, |_| {});
        assert!(matches!(
            r,
            Err(Bse2Error::SizeMismatch {
                expected: 10,
                actual: 0
            })
        ));
        assert!(matches!(
            encrypt(&b""[..], &mut Vec::new(), &key(), SALT, 0, 0, |_| {}),
            Err(Bse2Error::InvalidRecordSize(0))
        ));
    }
}
