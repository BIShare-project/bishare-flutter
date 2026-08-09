use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::constants::{Config, Port};

// ── Device Info ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub alias: String,
    #[serde(default = "default_version")]
    pub version: String,
    #[serde(rename = "deviceModel", skip_serializing_if = "Option::is_none")]
    pub device_model: Option<String>,
    #[serde(rename = "deviceType", skip_serializing_if = "Option::is_none")]
    pub device_type: Option<String>,
    pub fingerprint: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(rename = "protocol", default = "default_protocol")]
    pub protocol_: String,
    #[serde(default)]
    pub download: bool,
    #[serde(rename = "publicKey", skip_serializing_if = "Option::is_none")]
    pub public_key: Option<String>,
    #[serde(rename = "supportsBinary", skip_serializing_if = "Option::is_none")]
    pub supports_binary: Option<bool>,
    #[serde(rename = "supportsCompression", skip_serializing_if = "Option::is_none")]
    pub supports_compression: Option<bool>,
    #[serde(rename = "supportsKeepAlive", skip_serializing_if = "Option::is_none")]
    pub supports_keep_alive: Option<bool>,
    #[serde(rename = "supportsSync", skip_serializing_if = "Option::is_none")]
    pub supports_sync: Option<bool>,
    #[serde(rename = "supportsBroadcast", skip_serializing_if = "Option::is_none")]
    pub supports_broadcast: Option<bool>,
    #[serde(rename = "supportsMedia", skip_serializing_if = "Option::is_none")]
    pub supports_media: Option<bool>,
    #[serde(rename = "supportsResumeOffset", skip_serializing_if = "Option::is_none")]
    pub supports_resume_offset: Option<bool>,
    #[serde(rename = "supportsClipboardBinary", skip_serializing_if = "Option::is_none")]
    pub supports_clipboard_binary: Option<bool>,
    /// Self-reported LAN IPv4. Lets peers reach us at our real Wi-Fi address instead of a
    /// transport-resolved endpoint (over Apple AWDL, Bonjour resolves Apple↔Apple peers to an
    /// unreachable IPv6 link-local address).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ip: Option<String>,
}

fn default_version() -> String { Config::VERSION.to_string() }
fn default_port() -> u16 { Port::MAIN }
fn default_protocol() -> String { Config::PROTOCOL_SCHEME.to_string() }

impl Default for DeviceInfo {
    fn default() -> Self {
        Self {
            alias: String::new(),
            version: Config::VERSION.to_string(),
            device_model: None,
            device_type: None,
            fingerprint: String::new(),
            port: Port::MAIN,
            protocol_: Config::PROTOCOL_SCHEME.to_string(),
            download: false,
            public_key: None,
            supports_binary: Some(true),
            supports_compression: None,
            supports_keep_alive: None,
            supports_sync: None,
            supports_broadcast: None,
            supports_media: None,
            supports_resume_offset: None,
            supports_clipboard_binary: None,
            ip: None,
        }
    }
}

// ── File Metadata ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileMetadata {
    pub id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    pub size: i64,
    #[serde(rename = "fileType")]
    pub file_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
    #[serde(rename = "expiresInSeconds", skip_serializing_if = "Option::is_none")]
    pub expires_in_seconds: Option<i32>,
    /// Live Photo / motion photo pairing (v2.4): id of the paired asset
    #[serde(rename = "pairedId", skip_serializing_if = "Option::is_none")]
    pub paired_id: Option<String>,
    /// livePhotoStill | livePhotoMotion | motionPhoto | burst | raw | standalone
    #[serde(rename = "assetKind", skip_serializing_if = "Option::is_none")]
    pub asset_kind: Option<String>,
    /// primary | companion
    #[serde(rename = "pairRole", skip_serializing_if = "Option::is_none")]
    pub pair_role: Option<String>,
}

// ── Transfer Types ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareRequest {
    pub info: DeviceInfo,
    pub files: HashMap<String, FileMetadata>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareResponse {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub files: HashMap<String, String>, // fileId → token
    #[serde(rename = "publicKey", skip_serializing_if = "Option::is_none")]
    pub public_key: Option<String>,
    #[serde(rename = "maxConcurrent", skip_serializing_if = "Option::is_none")]
    pub max_concurrent: Option<usize>,
    #[serde(rename = "chunkSize", skip_serializing_if = "Option::is_none")]
    pub chunk_size: Option<usize>,
    #[serde(rename = "windowSize", skip_serializing_if = "Option::is_none")]
    pub window_size: Option<usize>,
    #[serde(rename = "supportsCompression", skip_serializing_if = "Option::is_none")]
    pub supports_compression: Option<bool>,
    #[serde(rename = "keepAlive", skip_serializing_if = "Option::is_none")]
    pub keep_alive: Option<bool>,
    #[serde(rename = "streamsPerFile", skip_serializing_if = "Option::is_none")]
    pub streams_per_file: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadResponse {
    pub success: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verified: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub encrypted: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub message: String,
}

// ── Session Types ──

#[derive(Debug, Clone)]
pub struct TransferSession {
    pub session_id: String,
    pub sender_info: DeviceInfo,
    pub files: HashMap<String, FileMetadata>,
    pub tokens: HashMap<String, String>,
    pub uploaded_files: std::collections::HashSet<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub encryption_key: Option<Vec<u8>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReceivedFile {
    pub id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    pub size: i64,
    #[serde(rename = "fileType")]
    pub file_type: String,
    #[serde(rename = "savedPath")]
    pub saved_path: String,
    #[serde(rename = "senderAlias")]
    pub sender_alias: String,
    #[serde(rename = "receivedAt")]
    pub received_at: i64, // unix timestamp ms
    pub verified: bool,
    #[serde(default)]
    pub encrypted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedFileInfo {
    pub index: usize,
    #[serde(rename = "fileName")]
    pub file_name: String,
    #[serde(rename = "fileType")]
    pub file_type: String,
    pub size: i64,
}

// ── Room Types ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomMember {
    pub fingerprint: String,
    pub alias: String,
    #[serde(rename = "deviceType")]
    pub device_type: String,
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomFileItem {
    pub id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    #[serde(rename = "fileType")]
    pub file_type: String,
    pub size: i64,
    #[serde(rename = "ownerAlias")]
    pub owner_alias: String,
    #[serde(rename = "ownerFingerprint")]
    pub owner_fingerprint: String,
    #[serde(rename = "addedAt", skip_serializing_if = "Option::is_none")]
    pub added_at: Option<String>,
    /// Room tree hierarchy (v2.4) — absent = flat legacy room
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(rename = "parentId", skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<String>,
    #[serde(rename = "isDir", skip_serializing_if = "Option::is_none")]
    pub is_dir: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomInfo {
    pub code: String,
    #[serde(rename = "hostAlias")]
    pub host_alias: String,
    #[serde(rename = "hostFingerprint")]
    pub host_fingerprint: String,
    #[serde(rename = "memberCount")]
    pub member_count: usize,
    #[serde(rename = "fileCount")]
    pub file_count: usize,
}

// ── Clipboard ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardPayload {
    #[serde(rename = "type", default = "clipboard_type")]
    pub type_: String,
    pub text: String,
    pub sender: String,
    pub alias: String,
    /// Binary clipboard (v2.4): text | image | file — absent = legacy text
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mime: Option<String>,
    #[serde(rename = "fileName", skip_serializing_if = "Option::is_none")]
    pub file_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub size: Option<u64>,
    /// Download token for out-of-band binary payload fetch
    #[serde(skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
}

fn clipboard_type() -> String { "clipboard".to_string() }

impl ClipboardPayload {
    pub fn new(text: String, sender_fingerprint: String, alias: String) -> Self {
        Self {
            type_: "clipboard".to_string(),
            text,
            sender: sender_fingerprint,
            alias,
            kind: None,
            mime: None,
            file_name: None,
            size: None,
            token: None,
            preview: None,
        }
    }
}

// ── Broadcast Types (v2.4) ──

/// Per-recipient wrapped content key for one-to-many transfer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecipientKey {
    pub fingerprint: String,
    #[serde(rename = "publicKey")]
    pub public_key: String,
    /// 60-byte envelope (nonce12 + ct32 + tag16) base64
    #[serde(rename = "wrappedKey")]
    pub wrapped_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BroadcastPrepareRequest {
    pub info: DeviceInfo,
    pub recipients: Vec<RecipientKey>,
    pub files: HashMap<String, FileMetadata>,
}

// ── WebRTC Signaling (v2.4) ──

/// Signaling envelope for Remote Camera / Screen Mirroring (frame 0x11 or relay WS)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalEnvelope {
    /// offer | answer | ice | bye | capability
    #[serde(rename = "type")]
    pub type_: String,
    #[serde(rename = "sessionId")]
    pub session_id: String,
    /// camera | screen
    pub media: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sdp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub candidate: Option<String>,
    #[serde(rename = "sdpMid", skip_serializing_if = "Option::is_none")]
    pub sdp_mid: Option<String>,
    #[serde(rename = "sdpMLineIndex", skip_serializing_if = "Option::is_none")]
    pub sdp_m_line_index: Option<i32>,
    pub sender: String,
    pub alias: String,
}

// ── File Request Types ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileRequestMessage {
    #[serde(rename = "requestId")]
    pub request_id: String,
    #[serde(rename = "requesterAlias")]
    pub requester_alias: String,
    #[serde(rename = "requesterFingerprint")]
    pub requester_fingerprint: String,
    #[serde(rename = "requesterHost")]
    pub requester_host: String,
    #[serde(rename = "requesterPort", default = "default_port")]
    pub requester_port: u16,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    #[serde(rename = "requestedTypes", skip_serializing_if = "Option::is_none")]
    pub requested_types: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileRequestResponse {
    #[serde(rename = "requestId")]
    pub request_id: String,
    pub accepted: bool,
}

// ── Goodbye ──

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoodbyeRequest {
    pub fingerprint: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn test_device_info_serializes_camel_case() {
        let info = DeviceInfo {
            alias: "MacBook".to_string(),
            device_model: Some("MacBookPro18,1".to_string()),
            device_type: Some("desktop".to_string()),
            fingerprint: "AA BB".to_string(),
            public_key: Some("cGs=".to_string()),
            supports_binary: Some(true),
            supports_compression: Some(true),
            supports_keep_alive: Some(true),
            ..Default::default()
        };
        let json = serde_json::to_string(&info).unwrap();
        assert!(json.contains("\"deviceModel\""));
        assert!(json.contains("\"publicKey\""));
        assert!(json.contains("\"supportsBinary\""));
        assert!(json.contains("\"supportsCompression\""));
        assert!(json.contains("\"supportsKeepAlive\""));
    }

    #[test]
    fn test_device_info_skips_none_fields() {
        let info = DeviceInfo {
            alias: "x".to_string(),
            fingerprint: "y".to_string(),
            supports_binary: None,
            ..Default::default()
        };
        let json = serde_json::to_string(&info).unwrap();
        assert!(!json.contains("deviceModel"));
        assert!(!json.contains("publicKey"));
        assert!(!json.contains("supportsBinary"));
        assert!(!json.contains("supportsCompression"));
        assert!(!json.contains("supportsKeepAlive"));
    }

    #[test]
    fn test_device_info_minimal_json_defaults() {
        let info: DeviceInfo = serde_json::from_str(r#"{"alias":"x","fingerprint":"y"}"#).unwrap();
        assert_eq!(info.alias, "x");
        assert_eq!(info.fingerprint, "y");
        assert_eq!(info.version, "2.4");
        assert_eq!(info.port, 58317);
        assert_eq!(info.protocol_, "https");
        assert!(!info.download);
        assert_eq!(info.public_key, None);
        assert_eq!(info.supports_binary, None);
        assert_eq!(info.supports_compression, None);
        assert_eq!(info.supports_keep_alive, None);
    }

    #[test]
    fn test_prepare_response_v23_fields() {
        let mut files = HashMap::new();
        files.insert("f1".to_string(), "token1".to_string());
        let resp = PrepareResponse {
            session_id: "s1".to_string(),
            files,
            public_key: None,
            max_concurrent: None,
            chunk_size: None,
            window_size: None,
            supports_compression: None,
            keep_alive: Some(true),
            streams_per_file: Some(4),
        };
        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains("\"keepAlive\":true"));
        assert!(json.contains("\"streamsPerFile\":4"));
        let parsed: PrepareResponse = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.keep_alive, Some(true));
        assert_eq!(parsed.streams_per_file, Some(4));
    }

    #[test]
    fn test_prepare_response_without_v23_fields() {
        let json = r#"{"sessionId":"s1","files":{"f1":"token1"}}"#;
        let parsed: PrepareResponse = serde_json::from_str(json).unwrap();
        assert_eq!(parsed.session_id, "s1");
        assert_eq!(parsed.keep_alive, None);
        assert_eq!(parsed.streams_per_file, None);
        // None fields skipped on re-serialization
        let json = serde_json::to_string(&parsed).unwrap();
        assert!(!json.contains("keepAlive"));
        assert!(!json.contains("streamsPerFile"));
    }

    #[test]
    fn test_file_metadata_roundtrip() {
        let meta = FileMetadata {
            id: "f1".to_string(),
            file_name: "photo.jpg".to_string(),
            size: 2048,
            file_type: "image/jpeg".to_string(),
            sha256: Some("hash".to_string()),
            preview: None,
            expires_in_seconds: Some(60),
            paired_id: None,
            asset_kind: None,
            pair_role: None,
        };
        let json = serde_json::to_string(&meta).unwrap();
        assert!(json.contains("\"fileName\""));
        assert!(json.contains("\"fileType\""));
        assert!(json.contains("\"expiresInSeconds\""));
        let parsed: FileMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.file_name, "photo.jpg");
        assert_eq!(parsed.expires_in_seconds, Some(60));
    }

    #[test]
    fn test_received_file_roundtrip() {
        let file = ReceivedFile {
            id: "f1".to_string(),
            file_name: "doc.pdf".to_string(),
            size: 1000,
            file_type: "application/pdf".to_string(),
            saved_path: "/tmp/doc.pdf".to_string(),
            sender_alias: "iPhone".to_string(),
            received_at: 1720000000000,
            verified: true,
            encrypted: false,
        };
        let json = serde_json::to_string(&file).unwrap();
        assert!(json.contains("\"savedPath\""));
        assert!(json.contains("\"senderAlias\""));
        assert!(json.contains("\"receivedAt\""));
        let parsed: ReceivedFile = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.saved_path, "/tmp/doc.pdf");
        assert!(parsed.verified);
    }

    #[test]
    fn test_room_info_roundtrip() {
        let info = RoomInfo {
            code: "ABCD".to_string(),
            host_alias: "Host".to_string(),
            host_fingerprint: "FP".to_string(),
            member_count: 2,
            file_count: 5,
        };
        let json = serde_json::to_string(&info).unwrap();
        assert!(json.contains("\"hostAlias\""));
        assert!(json.contains("\"hostFingerprint\""));
        assert!(json.contains("\"memberCount\""));
        assert!(json.contains("\"fileCount\""));
        let parsed: RoomInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.member_count, 2);
        assert_eq!(parsed.file_count, 5);
    }

    #[test]
    fn test_clipboard_payload() {
        let payload = ClipboardPayload::new("hello".to_string(), "FP".to_string(), "Mac".to_string());
        assert_eq!(payload.type_, "clipboard");
        let json = serde_json::to_string(&payload).unwrap();
        assert!(json.contains("\"type\":\"clipboard\""));
        let parsed: ClipboardPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.text, "hello");
        assert_eq!(parsed.sender, "FP");
    }

    #[test]
    fn test_device_info_v24_capability_flags() {
        let info = DeviceInfo {
            alias: "Mac".to_string(),
            fingerprint: "FP".to_string(),
            supports_sync: Some(true),
            supports_broadcast: Some(true),
            supports_media: Some(true),
            supports_resume_offset: Some(true),
            supports_clipboard_binary: Some(true),
            ..Default::default()
        };
        let json = serde_json::to_string(&info).unwrap();
        assert!(json.contains("\"supportsSync\":true"));
        assert!(json.contains("\"supportsBroadcast\":true"));
        assert!(json.contains("\"supportsMedia\":true"));
        assert!(json.contains("\"supportsResumeOffset\":true"));
        assert!(json.contains("\"supportsClipboardBinary\":true"));
        let parsed: DeviceInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.supports_sync, Some(true));
        assert_eq!(parsed.supports_clipboard_binary, Some(true));

        // Legacy 2.3 peer info without the flags → None, and None is never emitted
        let legacy: DeviceInfo = serde_json::from_str(r#"{"alias":"x","fingerprint":"y"}"#).unwrap();
        assert_eq!(legacy.supports_sync, None);
        assert_eq!(legacy.supports_broadcast, None);
        assert_eq!(legacy.supports_media, None);
        assert_eq!(legacy.supports_resume_offset, None);
        assert_eq!(legacy.supports_clipboard_binary, None);
        let json = serde_json::to_string(&legacy).unwrap();
        assert!(!json.contains("supportsSync"));
        assert!(!json.contains("supportsBroadcast"));
        assert!(!json.contains("supportsMedia"));
        assert!(!json.contains("supportsResumeOffset"));
        assert!(!json.contains("supportsClipboardBinary"));
    }

    #[test]
    fn test_file_metadata_v24_pairing_fields() {
        let meta = FileMetadata {
            id: "f1".to_string(),
            file_name: "IMG_0001.HEIC".to_string(),
            size: 4096,
            file_type: "image/heic".to_string(),
            sha256: None,
            preview: None,
            expires_in_seconds: None,
            paired_id: Some("f2".to_string()),
            asset_kind: Some("livePhotoStill".to_string()),
            pair_role: Some("primary".to_string()),
        };
        let json = serde_json::to_string(&meta).unwrap();
        assert!(json.contains("\"pairedId\":\"f2\""));
        assert!(json.contains("\"assetKind\":\"livePhotoStill\""));
        assert!(json.contains("\"pairRole\":\"primary\""));
        let parsed: FileMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.paired_id, Some("f2".to_string()));
        assert_eq!(parsed.asset_kind, Some("livePhotoStill".to_string()));
        assert_eq!(parsed.pair_role, Some("primary".to_string()));

        // Legacy 2.3 JSON without pairing fields → None, skipped on re-serialization
        let json = r#"{"id":"f1","fileName":"a.txt","size":1,"fileType":"text/plain"}"#;
        let parsed: FileMetadata = serde_json::from_str(json).unwrap();
        assert_eq!(parsed.paired_id, None);
        assert_eq!(parsed.asset_kind, None);
        assert_eq!(parsed.pair_role, None);
        let json = serde_json::to_string(&parsed).unwrap();
        assert!(!json.contains("pairedId"));
        assert!(!json.contains("assetKind"));
        assert!(!json.contains("pairRole"));
    }

    #[test]
    fn test_room_file_item_v24_tree_fields() {
        let item = RoomFileItem {
            id: "f1".to_string(),
            file_name: "notes.md".to_string(),
            file_type: "text/markdown".to_string(),
            size: 512,
            owner_alias: "Mac".to_string(),
            owner_fingerprint: "FP".to_string(),
            added_at: None,
            path: Some("docs/notes.md".to_string()),
            parent_id: Some("d1".to_string()),
            is_dir: Some(false),
        };
        let json = serde_json::to_string(&item).unwrap();
        assert!(json.contains("\"path\":\"docs/notes.md\""));
        assert!(json.contains("\"parentId\":\"d1\""));
        assert!(json.contains("\"isDir\":false"));
        let parsed: RoomFileItem = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.path, Some("docs/notes.md".to_string()));
        assert_eq!(parsed.parent_id, Some("d1".to_string()));
        assert_eq!(parsed.is_dir, Some(false));

        // Legacy flat-room JSON without tree fields → None, skipped on re-serialization
        let json = r#"{"id":"f1","fileName":"a.txt","fileType":"text/plain","size":1,"ownerAlias":"Mac","ownerFingerprint":"FP"}"#;
        let parsed: RoomFileItem = serde_json::from_str(json).unwrap();
        assert_eq!(parsed.path, None);
        assert_eq!(parsed.parent_id, None);
        assert_eq!(parsed.is_dir, None);
        let json = serde_json::to_string(&parsed).unwrap();
        assert!(!json.contains("\"path\""));
        assert!(!json.contains("parentId"));
        assert!(!json.contains("isDir"));
    }

    #[test]
    fn test_clipboard_payload_v24_binary_fields() {
        let mut payload = ClipboardPayload::new("".to_string(), "FP".to_string(), "Mac".to_string());
        payload.kind = Some("image".to_string());
        payload.mime = Some("image/png".to_string());
        payload.file_name = Some("screenshot.png".to_string());
        payload.size = Some(20480);
        payload.token = Some("tok".to_string());
        payload.preview = Some("cHJldmlldw==".to_string());
        let json = serde_json::to_string(&payload).unwrap();
        assert!(json.contains("\"kind\":\"image\""));
        assert!(json.contains("\"mime\":\"image/png\""));
        assert!(json.contains("\"fileName\":\"screenshot.png\""));
        assert!(json.contains("\"size\":20480"));
        assert!(json.contains("\"token\":\"tok\""));
        assert!(json.contains("\"preview\""));
        let parsed: ClipboardPayload = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.kind, Some("image".to_string()));
        assert_eq!(parsed.size, Some(20480));

        // Legacy 2.3 text-only JSON → None, skipped on re-serialization
        let json = r#"{"type":"clipboard","text":"hello","sender":"FP","alias":"Mac"}"#;
        let parsed: ClipboardPayload = serde_json::from_str(json).unwrap();
        assert_eq!(parsed.kind, None);
        assert_eq!(parsed.mime, None);
        assert_eq!(parsed.file_name, None);
        assert_eq!(parsed.size, None);
        assert_eq!(parsed.token, None);
        assert_eq!(parsed.preview, None);
        let json = serde_json::to_string(&parsed).unwrap();
        assert!(!json.contains("\"kind\""));
        assert!(!json.contains("\"mime\""));
        assert!(!json.contains("fileName"));
        assert!(!json.contains("\"token\""));
        assert!(!json.contains("\"preview\""));
    }

    #[test]
    fn test_broadcast_prepare_request_roundtrip() {
        let mut files = HashMap::new();
        files.insert("f1".to_string(), FileMetadata {
            id: "f1".to_string(),
            file_name: "a.txt".to_string(),
            size: 1,
            file_type: "text/plain".to_string(),
            sha256: None,
            preview: None,
            expires_in_seconds: None,
            paired_id: None,
            asset_kind: None,
            pair_role: None,
        });
        let req = BroadcastPrepareRequest {
            info: DeviceInfo { alias: "Mac".to_string(), fingerprint: "FP".to_string(), ..Default::default() },
            recipients: vec![RecipientKey {
                fingerprint: "AA BB".to_string(),
                public_key: "cGs=".to_string(),
                wrapped_key: "d3JhcHBlZA==".to_string(),
            }],
            files,
        };
        let json = serde_json::to_string(&req).unwrap();
        assert!(json.contains("\"recipients\""));
        assert!(json.contains("\"publicKey\":\"cGs=\""));
        assert!(json.contains("\"wrappedKey\":\"d3JhcHBlZA==\""));
        let parsed: BroadcastPrepareRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.recipients.len(), 1);
        assert_eq!(parsed.recipients[0].fingerprint, "AA BB");
        assert_eq!(parsed.recipients[0].wrapped_key, "d3JhcHBlZA==");
        assert_eq!(parsed.files.len(), 1);
    }

    #[test]
    fn test_signal_envelope_roundtrip() {
        let offer = SignalEnvelope {
            type_: "offer".to_string(),
            session_id: "s1".to_string(),
            media: "camera".to_string(),
            sdp: Some("v=0...".to_string()),
            candidate: None,
            sdp_mid: None,
            sdp_m_line_index: None,
            sender: "FP".to_string(),
            alias: "Mac".to_string(),
        };
        let json = serde_json::to_string(&offer).unwrap();
        assert!(json.contains("\"type\":\"offer\""));
        assert!(json.contains("\"sessionId\":\"s1\""));
        assert!(json.contains("\"media\":\"camera\""));
        assert!(json.contains("\"sdp\""));
        assert!(!json.contains("candidate"));
        assert!(!json.contains("sdpMid"));
        assert!(!json.contains("sdpMLineIndex"));
        let parsed: SignalEnvelope = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.type_, "offer");
        assert_eq!(parsed.sdp, Some("v=0...".to_string()));

        let ice = SignalEnvelope {
            type_: "ice".to_string(),
            session_id: "s1".to_string(),
            media: "screen".to_string(),
            sdp: None,
            candidate: Some("candidate:1".to_string()),
            sdp_mid: Some("0".to_string()),
            sdp_m_line_index: Some(0),
            sender: "FP".to_string(),
            alias: "Mac".to_string(),
        };
        let json = serde_json::to_string(&ice).unwrap();
        assert!(json.contains("\"candidate\":\"candidate:1\""));
        assert!(json.contains("\"sdpMid\":\"0\""));
        assert!(json.contains("\"sdpMLineIndex\":0"));
        let parsed: SignalEnvelope = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.candidate, Some("candidate:1".to_string()));
        assert_eq!(parsed.sdp_m_line_index, Some(0));
    }

    #[test]
    fn test_file_request_message_roundtrip() {
        let msg = FileRequestMessage {
            request_id: "r1".to_string(),
            requester_alias: "Mac".to_string(),
            requester_fingerprint: "FP".to_string(),
            requester_host: "192.168.1.2".to_string(),
            requester_port: 58317,
            message: Some("please".to_string()),
            requested_types: Some(vec!["image/*".to_string()]),
        };
        let json = serde_json::to_string(&msg).unwrap();
        assert!(json.contains("\"requestId\""));
        assert!(json.contains("\"requesterAlias\""));
        assert!(json.contains("\"requesterFingerprint\""));
        assert!(json.contains("\"requesterHost\""));
        assert!(json.contains("\"requesterPort\""));
        assert!(json.contains("\"requestedTypes\""));
        let parsed: FileRequestMessage = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.request_id, "r1");
        assert_eq!(parsed.requester_port, 58317);
    }
}
