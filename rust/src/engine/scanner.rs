//! Folder-sync filesystem scanner (Tahap 4 M1). Walks a pair root, stats every
//! entry, and hashes ONLY files whose `(size, mtimeMs)` changed vs a prior
//! snapshot (`SyncEntries`) — the Syncthing fast-path. Output entries match
//! `bishare_protocol::binary::BinaryManifestEntry` (`path,size,mtimeMs,sha256?,
//! isDir`) so they feed straight into `manifest_diff` on both the LAN and the
//! cloud path (§4.3).
//!
//! Pure Rust, never on the Dart event loop: the M1 FFI wrapper drives this from
//! FRB's worker pool and streams `on_batch` out over a `StreamSink`; batching +
//! a single reused read buffer keep peak RAM flat regardless of tree size
//! (risk #6). Hashing runs here, never in a Dart isolate (speed-fix lesson).

use std::collections::HashMap;
use std::fs;
use std::io::Read;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use sha2::{Digest, Sha256};

/// One scanned entry — the materialized manifest row for a path.
#[derive(Debug, Clone)]
pub struct ScanEntry {
    /// Path relative to the pair root, forward-slashed (stable across OSes).
    pub path: String,
    pub size: u64,
    pub mtime_ms: i64,
    /// Lowercase-hex SHA-256 of the content; `None` for directories and for
    /// files skipped as unstable (§4.2 stability check).
    pub sha256: Option<String>,
    pub is_dir: bool,
}

/// The prior manifest fact for a path — enough to decide "unchanged" without
/// re-hashing. Built from `SyncEntries` on the Dart side.
#[derive(Debug, Clone)]
pub struct PriorEntry {
    pub size: u64,
    pub mtime_ms: i64,
    pub sha256: String,
}

/// Knobs (M1 defaults; surfaced through the FFI later).
#[derive(Debug, Clone)]
pub struct ScanOptions {
    /// Flush a batch to `on_batch` once it reaches this many entries — bounds
    /// peak RAM (risk #6). 0 → flush once at the end.
    pub batch_size: usize,
    /// A file whose mtime is within this many ms of "now" is treated as still
    /// being written (editor temp-save, half-done download) and emitted WITHOUT
    /// a hash so the engine defers it (§4.2). 0 disables the check.
    pub stability_ms: i64,
    /// Read buffer for streaming hashes; bounds per-file hashing RAM.
    pub read_buf_bytes: usize,
}

impl Default for ScanOptions {
    fn default() -> Self {
        Self { batch_size: 512, stability_ms: 2_000, read_buf_bytes: 256 * 1024 }
    }
}

/// Counters returned once the walk completes — the raw material for the M0
/// bench numbers and for progress UI.
#[derive(Debug, Default, Clone)]
pub struct ScanStats {
    pub dirs: u64,
    pub files: u64,
    /// Files re-hashed because `(size, mtimeMs)` differed from the prior snapshot.
    pub hashed: u64,
    /// Files whose hash was reused from the prior snapshot (fast path).
    pub reused: u64,
    /// Files deferred by the stability check (emitted without a hash).
    pub unstable: u64,
    pub bytes_hashed: u64,
    /// Entries/paths that could not be stat-ed or read (permission, race).
    pub errors: u64,
}

fn mtime_ms(meta: &fs::Metadata) -> i64 {
    meta.modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut s = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        s.push(HEX[(b >> 4) as usize] as char);
        s.push(HEX[(b & 0x0f) as usize] as char);
    }
    s
}

/// Stream-hash a file with a caller-owned buffer (no per-file allocation).
fn hash_file(path: &Path, buf: &mut [u8]) -> std::io::Result<String> {
    let mut f = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    loop {
        let n = f.read(buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex_lower(&hasher.finalize()))
}

/// Relative, forward-slashed path of `p` under `root` (root itself → "").
fn rel_path(root: &Path, p: &Path) -> String {
    let rel = p.strip_prefix(root).unwrap_or(p);
    let s = rel.to_string_lossy();
    if std::path::MAIN_SEPARATOR == '/' {
        s.into_owned()
    } else {
        s.replace(std::path::MAIN_SEPARATOR, "/")
    }
}

/// Walk `root` recursively, stat every entry, and hash only files that changed
/// vs `prior` (keyed by the same relative path). Directories are emitted (dirs
/// carry `isDir:true`, no hash) so empty dirs sync. Symlinks are skipped (loop
/// safety; v1 non-goal). Entries stream out through `on_batch` in `batch_size`
/// chunks; the final partial batch flushes before returning `ScanStats`.
pub fn scan_and_hash<F: FnMut(Vec<ScanEntry>)>(
    root: &Path,
    prior: &HashMap<String, PriorEntry>,
    opts: &ScanOptions,
    mut on_batch: F,
) -> Result<ScanStats, String> {
    if !root.is_dir() {
        return Err(format!("scan root is not a directory: {}", root.display()));
    }
    let mut stats = ScanStats::default();
    let mut batch: Vec<ScanEntry> = Vec::with_capacity(opts.batch_size.max(1));
    let mut read_buf = vec![0u8; opts.read_buf_bytes.max(4096)];
    let now = now_ms();

    // Explicit stack instead of recursion: unbounded depth without blowing the
    // native stack, and deterministic memory.
    let mut stack: Vec<std::path::PathBuf> = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let rd = match fs::read_dir(&dir) {
            Ok(rd) => rd,
            Err(_) => {
                stats.errors += 1;
                continue;
            }
        };
        for ent in rd.flatten() {
            let path = ent.path();
            let meta = match fs::symlink_metadata(&path) {
                Ok(m) => m,
                Err(_) => {
                    stats.errors += 1;
                    continue;
                }
            };
            let ft = meta.file_type();
            if ft.is_symlink() {
                continue; // v1: symlinks not synced (loop/portability safety)
            }
            let rel = rel_path(root, &path);
            if ft.is_dir() {
                stats.dirs += 1;
                batch.push(ScanEntry {
                    path: rel,
                    size: 0,
                    mtime_ms: mtime_ms(&meta),
                    sha256: None,
                    is_dir: true,
                });
                stack.push(path);
            } else if ft.is_file() {
                stats.files += 1;
                let size = meta.len();
                let mt = mtime_ms(&meta);

                // Unchanged fast path: identical (size, mtimeMs) ⇒ reuse the
                // prior hash, never touch the file. mtime within 2s but same
                // size still re-hashes (FAT/exFAT 2s resolution, §4.3).
                let reuse = prior.get(&rel).and_then(|p| {
                    if p.size == size && p.mtime_ms == mt {
                        Some(p.sha256.clone())
                    } else {
                        None
                    }
                });

                let sha = if let Some(s) = reuse {
                    stats.reused += 1;
                    Some(s)
                } else if opts.stability_ms > 0 && (now - mt) < opts.stability_ms {
                    // Still settling — emit without a hash so the engine waits.
                    stats.unstable += 1;
                    None
                } else {
                    match hash_file(&path, &mut read_buf) {
                        Ok(s) => {
                            stats.hashed += 1;
                            stats.bytes_hashed += size;
                            Some(s)
                        }
                        Err(_) => {
                            stats.errors += 1;
                            None
                        }
                    }
                };

                batch.push(ScanEntry { path: rel, size, mtime_ms: mt, sha256: sha, is_dir: false });
            }

            if opts.batch_size > 0 && batch.len() >= opts.batch_size {
                on_batch(std::mem::take(&mut batch));
                batch = Vec::with_capacity(opts.batch_size);
            }
        }
    }
    if !batch.is_empty() {
        on_batch(batch);
    }
    Ok(stats)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Instant;

    #[test]
    fn empty_prior_hashes_everything_and_batches() {
        // A tiny synthetic tree under the OS temp dir.
        let root = std::env::temp_dir().join(format!("bishare-scan-t-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("sub")).unwrap();
        fs::write(root.join("a.txt"), b"hello").unwrap();
        fs::write(root.join("sub/b.txt"), b"world!!").unwrap();

        let prior = HashMap::new();
        let mut entries = Vec::new();
        // stability_ms 0: the just-written files must still be hashed here.
        let opts = ScanOptions { batch_size: 1, stability_ms: 0, ..Default::default() };
        let stats = scan_and_hash(&root, &prior, &opts, |b| entries.extend(b)).unwrap();

        assert_eq!(stats.files, 2);
        assert_eq!(stats.dirs, 1);
        assert_eq!(stats.hashed, 2);
        assert_eq!(stats.reused, 0);
        // SHA-256("hello") — locks the canonical lowercase-hex output.
        let a = entries.iter().find(|e| e.path == "a.txt").unwrap();
        assert_eq!(
            a.sha256.as_deref(),
            Some("2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        );
        let dir = entries.iter().find(|e| e.is_dir).unwrap();
        assert!(dir.sha256.is_none() && dir.path == "sub");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn matching_prior_reuses_hash_and_skips_read() {
        let root = std::env::temp_dir().join(format!("bishare-scan-r-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("a.txt"), b"hello").unwrap();
        let meta = fs::symlink_metadata(root.join("a.txt")).unwrap();

        let mut prior = HashMap::new();
        prior.insert(
            "a.txt".to_string(),
            PriorEntry { size: meta.len(), mtime_ms: mtime_ms(&meta), sha256: "deadbeef".into() },
        );
        let mut entries = Vec::new();
        let stats = scan_and_hash(&root, &prior, &ScanOptions::default(), |b| entries.extend(b))
            .unwrap();

        assert_eq!(stats.reused, 1);
        assert_eq!(stats.hashed, 0);
        // Reused verbatim (proves the file was never opened/hashed this round).
        assert_eq!(entries[0].sha256.as_deref(), Some("deadbeef"));
        let _ = fs::remove_dir_all(&root);
    }

    /// M0 bench — opt-in: `BISHARE_SCAN_ROOT=~/.pub-cache cargo test --release
    /// -p bishare_ffi bench_scan -- --nocapture --ignored`. Prints cold (hash
    /// all) + warm (reuse all) throughput; wrap with `/usr/bin/time -l` for RSS.
    #[test]
    #[ignore]
    fn bench_scan() {
        let Ok(root) = std::env::var("BISHARE_SCAN_ROOT") else {
            eprintln!("set BISHARE_SCAN_ROOT to a large dir to run this bench");
            return;
        };
        let root = std::path::PathBuf::from(shellexpand_tilde(&root));
        let opts = ScanOptions { stability_ms: 0, ..Default::default() };

        // Cold: empty prior → every file hashed.
        let mut snapshot: HashMap<String, PriorEntry> = HashMap::new();
        let t0 = Instant::now();
        let cold = scan_and_hash(&root, &HashMap::new(), &opts, |b| {
            for e in b {
                if !e.is_dir {
                    if let Some(s) = &e.sha256 {
                        snapshot.insert(e.path.clone(), PriorEntry { size: e.size, mtime_ms: e.mtime_ms, sha256: s.clone() });
                    }
                }
            }
        })
        .unwrap();
        let cold_secs = t0.elapsed().as_secs_f64();

        // Warm: full prior → walk + stat only, zero hashing.
        let t1 = Instant::now();
        let warm = scan_and_hash(&root, &snapshot, &opts, |_| {}).unwrap();
        let warm_secs = t1.elapsed().as_secs_f64();

        let total = cold.files + cold.dirs;
        let gb = cold.bytes_hashed as f64 / 1e9;
        eprintln!("\n── M0 scan_and_hash bench ── {}", root.display());
        eprintln!("entries: {} files + {} dirs = {}", cold.files, cold.dirs, total);
        eprintln!(
            "COLD (hash all): {:.2}s  |  {:.0} entries/s  |  {:.2} GB hashed  |  {:.0} MB/s hash  |  errors {}",
            cold_secs, total as f64 / cold_secs, gb, (gb * 1000.0) / cold_secs, cold.errors
        );
        eprintln!(
            "WARM (stat only, reuse {}): {:.2}s  |  {:.0} entries/s",
            warm.reused, warm_secs, total as f64 / warm_secs
        );
        eprintln!("→ extrapolated warm scan of 100k entries: {:.2}s\n", 100_000.0 * warm_secs / total as f64);
    }

    fn shellexpand_tilde(s: &str) -> String {
        if let Some(rest) = s.strip_prefix("~/") {
            if let Ok(home) = std::env::var("HOME") {
                return format!("{home}/{rest}");
            }
        }
        s.to_string()
    }
}
