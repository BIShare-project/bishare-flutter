//! FFI surface for the folder-sync filesystem scanner (Tahap 4 M1). Wraps
//! [`crate::engine::scanner::scan_and_hash`] and streams its batches to Dart so
//! the walk + hashing run entirely off the Dart isolate (hashing in Rust, never
//! a Dart isolate — speed-fix lesson). The heavy work runs on a dedicated thread
//! so a multi-second scan never occupies an FRB worker slot.

use std::collections::HashMap;
use std::path::Path;

use crate::engine::scanner::{scan_and_hash as engine_scan, PriorEntry, ScanOptions};
use crate::frb_generated::StreamSink;

/// One scanned entry crossing to Dart — mirrors
/// `bishare_protocol::binary::BinaryManifestEntry` so Dart can serialize a batch
/// straight into a manifest / `manifest_diff` input.
#[derive(Clone)]
pub struct FfiScanEntry {
    pub path: String,
    pub size: u64,
    pub mtime_ms: i64,
    /// Lowercase-hex SHA-256; `None` for directories and files skipped as
    /// unstable (still being written).
    pub sha256: Option<String>,
    pub is_dir: bool,
}

/// Final counters — emitted once, after the last [`ScanEvent::Batch`].
#[derive(Clone)]
pub struct FfiScanStats {
    pub dirs: u64,
    pub files: u64,
    pub hashed: u64,
    pub reused: u64,
    pub unstable: u64,
    pub bytes_hashed: u64,
    pub errors: u64,
}

/// Streamed scan progress: zero or more batches, then exactly one `Done`.
/// A fatal error (e.g. root missing) arrives via `sink.add_error`, not here.
#[derive(Clone)]
pub enum ScanEvent {
    Batch(Vec<FfiScanEntry>),
    Done(FfiScanStats),
}

/// A prior manifest fact from Dart (a `SyncEntries` row) — lets the scanner skip
/// re-hashing files whose `(size, mtimeMs)` are unchanged.
pub struct FfiPriorEntry {
    pub path: String,
    pub size: u64,
    pub mtime_ms: i64,
    pub sha256: String,
}

/// Walk `root`, hashing only files that changed vs `prior`, and stream
/// [`ScanEvent::Batch`]es followed by [`ScanEvent::Done`]. `batch_size` bounds
/// entries per batch (peak RAM); `stability_ms` defers files whose mtime is that
/// recent (partial writes). Runs on a dedicated thread and returns immediately;
/// a fatal error is delivered via `sink.add_error` (FRB sink-fn rule).
pub fn scan_and_hash(
    sink: StreamSink<ScanEvent>,
    root: String,
    prior: Vec<FfiPriorEntry>,
    batch_size: u32,
    stability_ms: i64,
) {
    std::thread::spawn(move || {
        let prior_map: HashMap<String, PriorEntry> = prior
            .into_iter()
            .map(|p| {
                (
                    p.path,
                    PriorEntry { size: p.size, mtime_ms: p.mtime_ms, sha256: p.sha256 },
                )
            })
            .collect();
        let opts = ScanOptions {
            batch_size: batch_size as usize,
            stability_ms,
            ..Default::default()
        };
        let result = engine_scan(Path::new(&root), &prior_map, &opts, |batch| {
            let mapped: Vec<FfiScanEntry> = batch
                .into_iter()
                .map(|e| FfiScanEntry {
                    path: e.path,
                    size: e.size,
                    mtime_ms: e.mtime_ms,
                    sha256: e.sha256,
                    is_dir: e.is_dir,
                })
                .collect();
            let _ = sink.add(ScanEvent::Batch(mapped));
        });
        match result {
            Ok(s) => {
                let _ = sink.add(ScanEvent::Done(FfiScanStats {
                    dirs: s.dirs,
                    files: s.files,
                    hashed: s.hashed,
                    reused: s.reused,
                    unstable: s.unstable,
                    bytes_hashed: s.bytes_hashed,
                    errors: s.errors,
                }));
            }
            Err(e) => {
                let _ = sink.add_error(e);
            }
        }
    });
}
