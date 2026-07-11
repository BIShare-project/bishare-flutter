//! Folder-sync manifest framing (0x0C/0x0D/0x0E) + tree diff. Payloads cross
//! the FFI as JSON strings of the `bishare_protocol::binary` structs — cheap,
//! and avoids mirroring them into FRB. Plain (non-`frb(sync)`) fns on purpose:
//! FRB runs them on its Rust worker pool, so diffing a large tree never blocks
//! the Dart event loop. v2.4 frames: never emit to a peer without
//! `supportsSync` (gating lives in Dart, later waves).

use bishare_protocol::binary::{
    BinaryManifestDelta, BinaryManifestEntry, BinaryManifestStart, DecodeResult, Decoder, DeltaOp,
    Encoder, MessageType,
};

/// Frame a `BinaryManifestStart` JSON string as a ManifestStart (0x0C) frame.
/// Round-trips through the protocol struct so the wire payload is exactly what
/// the peer's decoder expects (unknown/misspelled fields fail here, not there).
pub fn encode_manifest_start(start_json: String) -> Result<Vec<u8>, String> {
    let start: BinaryManifestStart = serde_json::from_str(&start_json)
        .map_err(|e| format!("invalid BinaryManifestStart: {e}"))?;
    Encoder::encode_json(MessageType::ManifestStart, 0, &start)
        .ok_or_else(|| "failed to encode ManifestStart frame".to_string())
}

/// Frame a `Vec<BinaryManifestEntry>` JSON string (one batch) as a
/// ManifestChunk (0x0D) frame.
pub fn encode_manifest_chunk(entries_json: String) -> Result<Vec<u8>, String> {
    let entries: Vec<BinaryManifestEntry> = serde_json::from_str(&entries_json)
        .map_err(|e| format!("invalid Vec<BinaryManifestEntry>: {e}"))?;
    Encoder::encode_json(MessageType::ManifestChunk, 0, &entries)
        .ok_or_else(|| "failed to encode ManifestChunk frame".to_string())
}

/// Frame a `BinaryManifestDelta` JSON string as a ManifestDelta (0x0E) frame.
pub fn encode_manifest_delta(delta_json: String) -> Result<Vec<u8>, String> {
    let delta: BinaryManifestDelta = serde_json::from_str(&delta_json)
        .map_err(|e| format!("invalid BinaryManifestDelta: {e}"))?;
    Encoder::encode_json(MessageType::ManifestDelta, 0, &delta)
        .ok_or_else(|| "failed to encode ManifestDelta frame".to_string())
}

/// Decode one complete manifest frame (0x0C/0x0D/0x0E) into a
/// `{"type": "manifestStart"|"manifestChunk"|"manifestDelta", "payload": …}`
/// JSON string, validating the payload against its protocol struct.
pub fn decode_manifest_frame(bytes: Vec<u8>) -> Result<String, String> {
    let frame = match Decoder::decode(&bytes) {
        DecodeResult::Success { frame, .. } => frame,
        DecodeResult::NeedMoreData => return Err("incomplete manifest frame".to_string()),
        DecodeResult::Error(e) => return Err(e),
    };
    let (type_name, payload) = match frame.msg_type {
        MessageType::ManifestStart => {
            let v: BinaryManifestStart = Decoder::decode_json(&frame)
                .ok_or_else(|| "malformed ManifestStart payload".to_string())?;
            ("manifestStart", serde_json::to_value(&v))
        }
        MessageType::ManifestChunk => {
            let v: Vec<BinaryManifestEntry> = Decoder::decode_json(&frame)
                .ok_or_else(|| "malformed ManifestChunk payload".to_string())?;
            ("manifestChunk", serde_json::to_value(&v))
        }
        MessageType::ManifestDelta => {
            let v: BinaryManifestDelta = Decoder::decode_json(&frame)
                .ok_or_else(|| "malformed ManifestDelta payload".to_string())?;
            ("manifestDelta", serde_json::to_value(&v))
        }
        other => {
            return Err(format!(
                "expected manifest frame (0x0C–0x0E), got 0x{:02X}",
                other as u8
            ));
        }
    };
    let payload = payload.map_err(|e| e.to_string())?;
    serde_json::to_string(&serde_json::json!({ "type": type_name, "payload": payload }))
        .map_err(|e| e.to_string())
}

/// Diff two manifests (`Vec<BinaryManifestEntry>` JSON ×2) into the
/// `Vec<DeltaOp>` JSON that transforms `local` into `remote`:
///
/// * **add** — path only in `remote`
/// * **modify** — path in both but size, sha256, mtime (or dir-ness) differ
/// * **delete** — path only in `local`
/// * **rename** — a delete+add pair with identical content (same `Some`
///   sha256 + same size) collapses into one op (`path` = old, `newPath` = new)
///
/// Ops are emitted adds → modifies → renames → deletes, each in input order,
/// so the result is deterministic.
pub fn manifest_diff(local_json: String, remote_json: String) -> Result<String, String> {
    let local: Vec<BinaryManifestEntry> = serde_json::from_str(&local_json)
        .map_err(|e| format!("invalid local manifest: {e}"))?;
    let remote: Vec<BinaryManifestEntry> = serde_json::from_str(&remote_json)
        .map_err(|e| format!("invalid remote manifest: {e}"))?;

    let local_by_path: std::collections::HashMap<&str, &BinaryManifestEntry> =
        local.iter().map(|e| (e.path.as_str(), e)).collect();
    let remote_by_path: std::collections::HashMap<&str, &BinaryManifestEntry> =
        remote.iter().map(|e| (e.path.as_str(), e)).collect();

    let mut adds: Vec<DeltaOp> = Vec::new();
    let mut modifies: Vec<DeltaOp> = Vec::new();
    for r in &remote {
        match local_by_path.get(r.path.as_str()) {
            None => adds.push(op_from_entry("add", r)),
            Some(l) => {
                if l.size != r.size
                    || l.sha256 != r.sha256
                    || l.mtime_ms != r.mtime_ms
                    || l.is_dir != r.is_dir
                {
                    modifies.push(op_from_entry("modify", r));
                }
            }
        }
    }

    // Rename detection: a deleted path whose content identity (sha256 + size)
    // reappears as an add is one rename, not a delete + re-transfer. Dirs and
    // unhashed entries (sha256 None) never pair.
    let mut renames: Vec<DeltaOp> = Vec::new();
    let mut deletes: Vec<DeltaOp> = Vec::new();
    for l in &local {
        if remote_by_path.contains_key(l.path.as_str()) {
            continue;
        }
        let matched = l.sha256.as_ref().and_then(|sha| {
            adds.iter()
                .position(|a| a.sha256.as_deref() == Some(sha) && a.size == Some(l.size))
        });
        match matched {
            Some(i) => {
                let add = adds.remove(i);
                renames.push(DeltaOp {
                    op: "rename".to_string(),
                    path: l.path.clone(),
                    new_path: Some(add.path),
                    sha256: add.sha256,
                    size: add.size,
                    mtime_ms: add.mtime_ms,
                    is_dir: add.is_dir,
                });
            }
            None => deletes.push(DeltaOp {
                op: "delete".to_string(),
                path: l.path.clone(),
                new_path: None,
                sha256: None,
                size: None,
                mtime_ms: None,
                is_dir: Some(l.is_dir),
            }),
        }
    }

    let ops: Vec<DeltaOp> = adds
        .into_iter()
        .chain(modifies)
        .chain(renames)
        .chain(deletes)
        .collect();
    serde_json::to_string(&ops).map_err(|e| e.to_string())
}

/// An add/modify op carrying the target (remote) state of the entry.
fn op_from_entry(op: &str, e: &BinaryManifestEntry) -> DeltaOp {
    DeltaOp {
        op: op.to_string(),
        path: e.path.clone(),
        new_path: None,
        sha256: e.sha256.clone(),
        size: Some(e.size),
        mtime_ms: Some(e.mtime_ms),
        is_dir: Some(e.is_dir),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(path: &str, size: u64, mtime_ms: i64, sha256: Option<&str>) -> serde_json::Value {
        let mut v = serde_json::json!({
            "path": path, "size": size, "mtimeMs": mtime_ms, "isDir": false,
        });
        if let Some(s) = sha256 {
            v["sha256"] = serde_json::Value::String(s.to_string());
        }
        v
    }

    #[test]
    fn test_manifest_frame_roundtrips() {
        let start = r#"{"syncId":"s1","rootName":"Docs","totalEntries":2,"cursor":7,"manifestHash":"ab"}"#;
        let bytes = encode_manifest_start(start.to_string()).unwrap();
        assert_eq!(bytes[0], 0x0C); // wire byte stays ManifestStart
        let decoded: serde_json::Value =
            serde_json::from_str(&decode_manifest_frame(bytes).unwrap()).unwrap();
        assert_eq!(decoded["type"], "manifestStart");
        assert_eq!(decoded["payload"]["syncId"], "s1");

        let chunk = serde_json::json!([entry("a.txt", 3, 1000, Some("aa"))]).to_string();
        let bytes = encode_manifest_chunk(chunk).unwrap();
        assert_eq!(bytes[0], 0x0D);
        let decoded: serde_json::Value =
            serde_json::from_str(&decode_manifest_frame(bytes).unwrap()).unwrap();
        assert_eq!(decoded["type"], "manifestChunk");
        assert_eq!(decoded["payload"][0]["path"], "a.txt");

        let delta = r#"{"syncId":"s1","baseCursor":7,"newCursor":8,"ops":[{"op":"delete","path":"a.txt"}]}"#;
        let bytes = encode_manifest_delta(delta.to_string()).unwrap();
        assert_eq!(bytes[0], 0x0E);
        let decoded: serde_json::Value =
            serde_json::from_str(&decode_manifest_frame(bytes).unwrap()).unwrap();
        assert_eq!(decoded["type"], "manifestDelta");
        assert_eq!(decoded["payload"]["ops"][0]["op"], "delete");
    }

    #[test]
    fn test_decode_manifest_frame_rejects_non_manifest() {
        let frame = Encoder::encode(MessageType::Ack, 0, b"{}");
        assert!(decode_manifest_frame(frame).is_err());
        assert!(decode_manifest_frame(vec![0x0C]).is_err()); // truncated
        assert!(encode_manifest_start("{".to_string()).is_err());
    }

    #[test]
    fn test_manifest_diff_add_modify_delete() {
        let local = serde_json::json!([
            entry("same.txt", 1, 100, Some("s1")),
            entry("changed.txt", 2, 200, Some("c1")),
            entry("gone.txt", 3, 300, None),
        ])
        .to_string();
        let remote = serde_json::json!([
            entry("same.txt", 1, 100, Some("s1")),
            entry("changed.txt", 2, 999, Some("c2")),
            entry("new.txt", 4, 400, Some("n1")),
        ])
        .to_string();

        let ops: Vec<serde_json::Value> =
            serde_json::from_str(&manifest_diff(local, remote).unwrap()).unwrap();
        let kinds: Vec<(&str, &str)> = ops
            .iter()
            .map(|o| (o["op"].as_str().unwrap(), o["path"].as_str().unwrap()))
            .collect();
        assert_eq!(
            kinds,
            vec![
                ("add", "new.txt"),
                ("modify", "changed.txt"),
                ("delete", "gone.txt"),
            ]
        );
        // add/modify carry the target (remote) state
        assert_eq!(ops[1]["mtimeMs"], 999);
        assert_eq!(ops[1]["sha256"], "c2");
        // file ops carry isDir so a receiver can tell dirs from empty files
        assert_eq!(ops[0]["isDir"], false);
        assert_eq!(ops[2]["isDir"], false);
    }

    #[test]
    fn test_manifest_diff_directory_add_carries_is_dir() {
        let dir = serde_json::json!({
            "path": "docs", "size": 0, "mtimeMs": 100, "isDir": true,
        });
        let local = serde_json::json!([]).to_string();
        let remote =
            serde_json::json!([dir, entry("docs/a.txt", 3, 200, Some("aa"))]).to_string();

        let ops: Vec<serde_json::Value> =
            serde_json::from_str(&manifest_diff(local, remote).unwrap()).unwrap();
        let docs = ops.iter().find(|o| o["path"] == "docs").unwrap();
        // Without isDir a directory add is indistinguishable from an empty file.
        assert_eq!(docs["op"], "add");
        assert_eq!(docs["isDir"], true);
        let file = ops.iter().find(|o| o["path"] == "docs/a.txt").unwrap();
        assert_eq!(file["isDir"], false);
    }

    #[test]
    fn test_manifest_diff_detects_rename() {
        let local = serde_json::json!([entry("old/name.bin", 5, 100, Some("deadbeef"))]).to_string();
        let remote =
            serde_json::json!([entry("new/name.bin", 5, 150, Some("deadbeef"))]).to_string();

        let ops: Vec<serde_json::Value> =
            serde_json::from_str(&manifest_diff(local, remote).unwrap()).unwrap();
        assert_eq!(ops.len(), 1);
        assert_eq!(ops[0]["op"], "rename");
        assert_eq!(ops[0]["path"], "old/name.bin");
        assert_eq!(ops[0]["newPath"], "new/name.bin");

        // Same sha but different size ⇒ NOT a rename (delete + add)
        let local = serde_json::json!([entry("a.bin", 5, 100, Some("deadbeef"))]).to_string();
        let remote = serde_json::json!([entry("b.bin", 6, 100, Some("deadbeef"))]).to_string();
        let ops: Vec<serde_json::Value> =
            serde_json::from_str(&manifest_diff(local, remote).unwrap()).unwrap();
        let kinds: Vec<&str> = ops.iter().map(|o| o["op"].as_str().unwrap()).collect();
        assert_eq!(kinds, vec!["add", "delete"]);
    }
}
