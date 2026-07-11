//! Durable resume ledger (Phase 4, hte-architecture.md §7.2): a small sidecar
//! next to the pre-allocated `.part` that records which chunks are already on
//! disk, so a transfer interrupted by network drop / app kill / power loss
//! resumes from the last fsync'd chunk instead of restarting from zero.
//!
//! ## Durability contract (strict ordering)
//! The receiver fsyncs the `.part` DATA first, then writes+fsyncs the ledger.
//! So the ledger can never claim a chunk the disk doesn't hold — a crash at any
//! point leaves the ledger describing a subset of what's actually written
//! (safe: at worst a few durable chunks are re-sent). The ledger is written
//! atomically (temp + rename) and CRC-protected; a torn/corrupt ledger is
//! ignored (fresh start), never trusted.
//!
//! ## Identity
//! The `.part` is named by a stable `resume_key` (sender-derived from
//! fingerprint+name+size, NOT the per-transfer sessionId), so a reconnect under
//! a fresh session still matches its partial file. A geometry/key mismatch
//! discards the stale partial. Final Merkle verification is the backstop: if the
//! partial's bytes don't match (e.g. the file changed), the whole transfer fails
//! closed and restarts clean.

use std::io::Write;

const MAGIC: &[u8; 8] = b"BISHRZ\x01\x00";

/// Sidecar path for a `.part` file.
pub fn ledger_path(part_path: &str) -> String {
    format!("{part_path}.rz")
}

/// Geometry a ledger must match to be reused.
pub struct LedgerMeta<'a> {
    pub size: u64,
    pub chunk_size: u32,
    pub total_chunks: u64,
    pub resume_key: &'a str,
}

/// Load the bitmap words from an existing, valid ledger that matches `meta`.
/// Returns `None` when there is no ledger, it is corrupt, or its geometry/key
/// differs (caller then starts fresh).
pub fn load(part_path: &str, meta: &LedgerMeta) -> Option<Vec<u64>> {
    let raw = std::fs::read(ledger_path(part_path)).ok()?;
    if raw.len() < 8 + 8 + 4 + 8 + 2 + 4 || &raw[..8] != MAGIC {
        return None;
    }
    // Verify the trailing CRC over everything before it.
    let body = &raw[..raw.len() - 4];
    let stored_crc = u32::from_le_bytes(raw[raw.len() - 4..].try_into().ok()?);
    if crc32c::crc32c(body) != stored_crc {
        return None;
    }

    let mut p = 8;
    let size = u64::from_le_bytes(raw[p..p + 8].try_into().ok()?);
    p += 8;
    let chunk_size = u32::from_le_bytes(raw[p..p + 4].try_into().ok()?);
    p += 4;
    let total_chunks = u64::from_le_bytes(raw[p..p + 8].try_into().ok()?);
    p += 8;
    let key_len = u16::from_le_bytes(raw[p..p + 2].try_into().ok()?) as usize;
    p += 2;
    let key = raw.get(p..p + key_len)?;
    p += key_len;

    // Geometry must match exactly, else the partial is for a different transfer.
    if size != meta.size
        || chunk_size != meta.chunk_size
        || total_chunks != meta.total_chunks
        || key != meta.resume_key.as_bytes()
    {
        return None;
    }

    let words = total_chunks.div_ceil(64) as usize;
    let bitmap_bytes = words * 8;
    let bitmap = raw.get(p..p + bitmap_bytes)?;
    if p + bitmap_bytes != raw.len() - 4 {
        return None; // trailing junk / size mismatch
    }
    let mut bits = Vec::with_capacity(words);
    for w in bitmap.chunks_exact(8) {
        bits.push(u64::from_le_bytes(w.try_into().ok()?));
    }
    Some(bits)
}

/// Atomically persist `bits` for `part_path`. Caller must have fsync'd the
/// `.part` data first (durability ordering).
pub fn save(part_path: &str, meta: &LedgerMeta, bits: &[u64]) -> std::io::Result<()> {
    let mut buf = Vec::with_capacity(30 + meta.resume_key.len() + bits.len() * 8);
    buf.extend_from_slice(MAGIC);
    buf.extend_from_slice(&meta.size.to_le_bytes());
    buf.extend_from_slice(&meta.chunk_size.to_le_bytes());
    buf.extend_from_slice(&meta.total_chunks.to_le_bytes());
    buf.extend_from_slice(&(meta.resume_key.len() as u16).to_le_bytes());
    buf.extend_from_slice(meta.resume_key.as_bytes());
    for w in bits {
        buf.extend_from_slice(&w.to_le_bytes());
    }
    let crc = crc32c::crc32c(&buf);
    buf.extend_from_slice(&crc.to_le_bytes());

    let tmp = format!("{}.tmp", ledger_path(part_path));
    {
        let mut f = std::fs::File::create(&tmp)?;
        f.write_all(&buf)?;
        f.sync_all()?;
    }
    std::fs::rename(&tmp, ledger_path(part_path))
}

/// Remove the ledger (on successful completion or a fatal integrity failure).
pub fn remove(part_path: &str) {
    let _ = std::fs::remove_file(ledger_path(part_path));
    let _ = std::fs::remove_file(format!("{}.tmp", ledger_path(part_path)));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ledger_roundtrip_and_geometry_guard() {
        let dir = std::env::temp_dir().join(format!("rz_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let part = dir.join("x.part").to_string_lossy().to_string();
        let meta = LedgerMeta { size: 300_000, chunk_size: 65536, total_chunks: 5, resume_key: "abc" };
        let bits = vec![0b10110u64]; // chunks 1,2,4 present

        save(&part, &meta, &bits).unwrap();
        assert_eq!(load(&part, &meta), Some(bits.clone()));

        // Wrong geometry → no reuse.
        let bad = LedgerMeta { size: 300_001, ..LedgerMeta { size: 0, chunk_size: 65536, total_chunks: 5, resume_key: "abc" } };
        assert_eq!(load(&part, &bad), None);
        let badkey = LedgerMeta { resume_key: "def", ..LedgerMeta { size: 300_000, chunk_size: 65536, total_chunks: 5, resume_key: "" } };
        assert_eq!(load(&part, &badkey), None);

        // Corruption → ignored.
        let mut raw = std::fs::read(ledger_path(&part)).unwrap();
        let n = raw.len();
        raw[n - 6] ^= 0xFF;
        std::fs::write(ledger_path(&part), &raw).unwrap();
        assert_eq!(load(&part, &meta), None);

        remove(&part);
        assert_eq!(load(&part, &meta), None);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
