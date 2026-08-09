/// BIShare Protocol Configuration
pub struct Config;

impl Config {
    pub const VERSION: &str = "2.4";
    pub const PROTOCOL_SCHEME: &str = "https";
    pub const SCHEME: &str = "bishare";
    pub const CODE_CHARSET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    pub const ROOM_CODE_LENGTH: usize = 4;
    pub const MAX_RECEIVED_FILES_IN_MEMORY: usize = 100;
    pub const CLIPBOARD_HISTORY_MAX: usize = 20;
    pub const CLIPBOARD_POLL_INTERVAL_SECS: f64 = 2.0;
    pub const ACCEPT_REJECT_TIMEOUT_SECS: f64 = 30.0;
    pub const STALE_DEVICE_TIMEOUT_SECS: f64 = 15.0;
    pub const DEFAULT_MAX_CONCURRENT: usize = 4;

    // Binary protocol v2.1+
    pub const BINARY_PROTOCOL_MIN_VERSION: &str = "2.1";
    pub const BINARY_PORT_OFFSET: u16 = 2;

    // Speed protocol v2.2
    pub const SPEED_PROTOCOL_MIN_VERSION: &str = "2.2";
    pub const DEFAULT_CHUNK_SIZE: usize = 256 * 1024; // 256KB
    pub const MIN_CHUNK_SIZE: usize = 64 * 1024; // 64KB
    pub const MAX_CHUNK_SIZE: usize = 1024 * 1024; // 1MB
    pub const DEFAULT_MAX_CONCURRENT_V2: usize = 8;
    pub const DEFAULT_WINDOW_SIZE: usize = 16;
    pub const COMPRESSION_MIN_SIZE: usize = 1024;

    // P2P protocol v2.3
    pub const P2P_PROTOCOL_MIN_VERSION: &str = "2.3";
    pub const DEFAULT_STREAMS_PER_FILE: usize = 4;

    // Premium features v2.4
    pub const SYNC_PROTOCOL_MIN_VERSION: &str = "2.4";
    pub const BROADCAST_PROTOCOL_MIN_VERSION: &str = "2.4";
    pub const MEDIA_PROTOCOL_MIN_VERSION: &str = "2.4";
    pub const CLIPBOARD_BINARY_MIN_VERSION: &str = "2.4";
    pub const RESUME_OFFSET_MIN_VERSION: &str = "2.4";

    pub const COMPRESSIBLE_MIME_PREFIXES: &[&str] = &[
        "text/",
        "application/json",
        "application/xml",
        "application/javascript",
        "application/x-yaml",
        "application/svg+xml",
        "application/xhtml+xml",
    ];

    pub fn is_compressible(mime_type: &str) -> bool {
        let lower = mime_type.to_lowercase();
        Self::COMPRESSIBLE_MIME_PREFIXES
            .iter()
            .any(|prefix| lower.starts_with(prefix))
    }
}

/// Network Ports
pub struct Port;

impl Port {
    pub const MAIN: u16 = 58317; // TCP HTTP
    pub const QUIC: u16 = 58318; // UDP QUIC (always-on HTE endpoint)
    pub const ROOM: u16 = 58319; // TCP Room HTTP
    pub const WEBDAV: u16 = 58320; // TCP WebDAV
    /// Universal-clipboard sync — UDP. Its own port: the Dart clipboard datagram
    /// channel must not share [`QUIC`], which the always-on QUIC endpoint binds.
    pub const CLIPBOARD: u16 = 58321; // UDP clipboard announce
}

/// Bonjour/mDNS Service Types
pub struct ServiceType;

impl ServiceType {
    /// Register WITH trailing dot (Android format), match both when browsing
    pub const DISCOVERY: &str = "_bishare._tcp.local.";
    pub const DISCOVERY_RAW: &str = "_bishare._tcp";
    pub const ROOM: &str = "_bishare-room._tcp.local.";
    pub const ROOM_RAW: &str = "_bishare-room._tcp";
    pub const NEARBY: &str = "bishare-nearby";
    pub const QUIC_ALPN: &[&str] = &["bishare-quic"];
    /// Wi-Fi Aware service type for iOS 26+ WiFiAwareServices
    pub const AWARE: &str = "_bishare-aware._tcp";
    /// Android Wi-Fi Aware NAN service name
    pub const AWARE_NAN: &str = "bishare-aware";
}

/// Cryptographic Constants
pub struct Crypto;

impl Crypto {
    pub const E2E_SALT: &[u8] = b"BIShare-E2E";
    pub const E2E_INFO: &[u8] = b"file-transfer";
    pub const AES_KEY_SIZE: usize = 32;
    pub const GCM_NONCE_SIZE: usize = 12;
    pub const GCM_TAG_BITS: usize = 128;
    pub const FINGERPRINT_BYTES: usize = 8;
    pub const GCM_OVERHEAD_PER_CHUNK: usize = Self::GCM_NONCE_SIZE + (Self::GCM_TAG_BITS / 8); // 28
}

/// API Endpoint Paths
pub struct ApiPath;

impl ApiPath {
    // Transfer endpoints (main port)
    pub const INFO: &str = "/api/v1/info";
    pub const PREPARE: &str = "/api/v1/prepare";
    pub const UPLOAD: &str = "/api/v1/upload";
    pub const CANCEL: &str = "/api/v1/cancel";
    pub const FILES: &str = "/api/v1/files";
    pub const DOWNLOAD: &str = "/api/v1/download";
    pub const DOWNLOAD_ALL: &str = "/api/v1/download-all";
    pub const BROWSER_UPLOAD: &str = "/api/v1/browser-upload";
    pub const INSTANT: &str = "/api/v1/instant";
    pub const REQUEST: &str = "/api/v1/request";
    pub const VERIFY_PIN: &str = "/api/v1/verify-pin";
    pub const GOODBYE: &str = "/api/v1/goodbye";

    // Premium feature endpoints v2.4 (main port)
    pub const CLIPBOARD: &str = "/api/v1/clipboard";
    pub const SIGNAL: &str = "/api/v1/signal";
    pub const SYNC: &str = "/api/v1/sync";
    pub const MANIFEST: &str = "/api/v1/manifest";
    pub const BROADCAST_PREPARE: &str = "/api/v1/broadcast/prepare";

    // Room endpoints (room port)
    pub const ROOM_INFO: &str = "/api/v1/room/info";
    pub const ROOM_JOIN: &str = "/api/v1/room/join";
    pub const ROOM_FILES: &str = "/api/v1/room/files";
    pub const ROOM_DOWNLOAD: &str = "/api/v1/room/download";
    pub const ROOM_FILE_ADDED: &str = "/api/v1/room/file-added";
    pub const ROOM_KICKED: &str = "/api/v1/room/kicked";
    pub const ROOM_MEMBER_JOINED: &str = "/api/v1/room/member-joined";
    pub const ROOM_MEMBER_LEFT: &str = "/api/v1/room/member-left";
    pub const ROOM_TREE: &str = "/api/v1/room/tree";
}

/// File Categories
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileCategory {
    Images,
    Videos,
    Audio,
    Documents,
    Archives,
    Other,
}

impl FileCategory {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Images => "Images",
            Self::Videos => "Videos",
            Self::Audio => "Audio",
            Self::Documents => "Documents",
            Self::Archives => "Archives",
            Self::Other => "Other",
        }
    }

    pub fn from_mime(mime_type: &str) -> Self {
        let lower = mime_type.to_lowercase();
        if lower.starts_with("image/") {
            Self::Images
        } else if lower.starts_with("video/") {
            Self::Videos
        } else if lower.starts_with("audio/") {
            Self::Audio
        } else if lower.starts_with("text/") || lower.contains("pdf") {
            Self::Documents
        } else if lower.contains("zip")
            || lower.contains("tar")
            || lower.contains("compress")
            || lower.contains("archive")
        {
            Self::Archives
        } else {
            Self::Other
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn test_protocol_versions() {
        assert_eq!(Config::VERSION, "2.4");
        assert_eq!(Config::P2P_PROTOCOL_MIN_VERSION, "2.3");
        assert_eq!(Config::DEFAULT_STREAMS_PER_FILE, 4);
        assert_eq!(Config::SYNC_PROTOCOL_MIN_VERSION, "2.4");
        assert_eq!(Config::BROADCAST_PROTOCOL_MIN_VERSION, "2.4");
        assert_eq!(Config::MEDIA_PROTOCOL_MIN_VERSION, "2.4");
        assert_eq!(Config::CLIPBOARD_BINARY_MIN_VERSION, "2.4");
        assert_eq!(Config::RESUME_OFFSET_MIN_VERSION, "2.4");
    }

    #[test]
    fn test_v24_api_paths() {
        assert_eq!(ApiPath::CLIPBOARD, "/api/v1/clipboard");
        assert_eq!(ApiPath::SIGNAL, "/api/v1/signal");
        assert_eq!(ApiPath::SYNC, "/api/v1/sync");
        assert_eq!(ApiPath::MANIFEST, "/api/v1/manifest");
        assert_eq!(ApiPath::BROADCAST_PREPARE, "/api/v1/broadcast/prepare");
        assert_eq!(ApiPath::ROOM_TREE, "/api/v1/room/tree");
    }

    #[test]
    fn test_ports() {
        assert_eq!(Port::MAIN, 58317);
        assert_eq!(Port::QUIC, 58318);
        assert_eq!(Port::ROOM, 58319);
        assert_eq!(Port::WEBDAV, 58320);
        assert_eq!(Port::CLIPBOARD, 58321);
    }

    #[test]
    fn test_gcm_overhead_per_chunk() {
        assert_eq!(Crypto::GCM_OVERHEAD_PER_CHUNK, 28);
    }

    #[test]
    fn test_aware_service_types() {
        assert_eq!(ServiceType::AWARE, "_bishare-aware._tcp");
        assert_eq!(ServiceType::AWARE_NAN, "bishare-aware");
    }

    #[test]
    fn test_file_category_from_mime() {
        assert_eq!(FileCategory::from_mime("image/png"), FileCategory::Images);
        assert_eq!(FileCategory::from_mime("video/quicktime"), FileCategory::Videos);
        assert_eq!(FileCategory::from_mime("audio/mpeg"), FileCategory::Audio);
        assert_eq!(FileCategory::from_mime("application/pdf"), FileCategory::Documents);
        assert_eq!(FileCategory::from_mime("application/x-tar"), FileCategory::Archives);
        assert_eq!(FileCategory::from_mime("application/octet-stream"), FileCategory::Other);
    }
}
