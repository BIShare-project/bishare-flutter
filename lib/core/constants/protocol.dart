/// BIShare protocol constants — a byte-for-byte port of the native
/// `BIShareProtocol` Swift package (and its Kotlin/Rust twins). These values are
/// wire-visible and cross-platform: changing any of them breaks interop with
/// existing iOS/Android/desktop peers, so they are grounded directly against
/// `bishare-protocol/ios/Sources/BIShareProtocol/Constants/*`.
library;

/// Network ports (all in the dynamic/private range 49152–65535).
class BISharePort {
  BISharePort._();

  /// Main transfer server — TCP HTTP.
  static const int main = 58317;

  /// QUIC transport — UDP. Always-on (the Rust HTE engine owns this socket), so
  /// the Dart clipboard datagram channel must NOT reuse it — see [clipboard].
  static const int quic = 58318;

  /// Transfer Rooms — TCP HTTP.
  static const int room = 58319;

  /// WebDAV server — TCP.
  static const int webdav = 58320;

  /// Universal-clipboard sync — UDP. Its OWN port (not [quic], which the
  /// always-on Rust QUIC endpoint already binds — a shared port made the Dart
  /// clipboard socket fail to bind). Advertised in the mDNS TXT (`clipPort`) so
  /// 2.4 peers announce here; the value is a fixed constant across builds, so
  /// senders can also target it directly without reading the TXT.
  static const int clipboard = 58321;
}

/// Bonjour/mDNS service types and ALPN identifiers.
class BIShareService {
  BIShareService._();

  /// Main device discovery service type.
  static const String discovery = '_bishare._tcp';

  /// Transfer-room discovery service type.
  static const String room = '_bishare-room._tcp';

  /// MultipeerConnectivity nearby service type.
  static const String nearby = 'bishare-nearby';

  /// QUIC ALPN protocol identifier.
  static const List<String> quicAlpn = ['bishare-quic'];

  /// Wi-Fi Aware service type (iOS 26+).
  static const String aware = '_bishare-aware._tcp';

  /// Android Wi-Fi Aware (NAN) service name.
  static const String awareNan = 'bishare-aware';
}

/// HTTP API endpoint paths.
class BIShareApi {
  BIShareApi._();

  // Transfer endpoints (port [BISharePort.main]).
  static const String info = '/api/v1/info';
  static const String prepare = '/api/v1/prepare';
  static const String upload = '/api/v1/upload';
  static const String cancel = '/api/v1/cancel';
  static const String files = '/api/v1/files';
  static const String download = '/api/v1/download';
  static const String downloadAll = '/api/v1/download-all';
  static const String browserUpload = '/api/v1/browser-upload';
  static const String instant = '/api/v1/instant';
  static const String request = '/api/v1/request';
  static const String verifyPin = '/api/v1/verify-pin';
  static const String goodbye = '/api/v1/goodbye';

  /// Binary-clipboard pull (v2.4, mirrors Rust `ApiPath::CLIPBOARD`) — a
  /// receiver GETs the announced image with `?token=` (one-shot, 60s TTL).
  static const String clipboard = '/api/v1/clipboard';

  /// Folder-sync manifest exchange (Tahap 4, mirrors Rust `ApiPath::SYNC`) —
  /// a paired peer POSTs an AEAD-encrypted manifest frame (0x0C–0x0E) and gets
  /// an encrypted ack (needed-files list) back. See `SyncEngine`.
  static const String sync = '/api/v1/sync';

  // Browser Web-Share extensions (feature #11). Served only to web browsers,
  // never to app peers, so they need no protocol mirror — an older server
  // simply 404s, which the page treats as "feature unavailable" (natural
  // fallback per F.1.a).
  /// Folder listing for the browser's tree view (`?path=<rel>`).
  static const String browse = '/api/v1/browse';

  /// Streaming zip of a folder under the share root (`?path=<rel>`).
  static const String downloadFolder = '/download-folder';

  /// Single-file download by validated relative path (`?path=<rel>`).
  static const String downloadFile = '/api/v1/download-file';

  /// Chunked resumable browser upload (headers `X-Upload-Id`,
  /// `X-Chunk-Offset`, final chunk `X-Upload-Complete: 1`).
  static const String browserUploadChunk = '/api/v1/browser-upload-chunk';

  /// Resume probe: `?id=` → `{offset}` (the `.part` length on disk).
  static const String browserUploadStatus = '/api/v1/browser-upload-status';

  // Room endpoints (port [BISharePort.room]).
  static const String roomInfo = '/api/v1/room/info';
  static const String roomJoin = '/api/v1/room/join';
  static const String roomFiles = '/api/v1/room/files';
  static const String roomDownload = '/api/v1/room/download';
  static const String roomFileAdded = '/api/v1/room/file-added';
  static const String roomKicked = '/api/v1/room/kicked';
  static const String roomMemberJoined = '/api/v1/room/member-joined';
  static const String roomMemberLeft = '/api/v1/room/member-left';
}

/// Protocol-level configuration constants.
class BIShareConfig {
  BIShareConfig._();

  /// Protocol version advertised in `DeviceInfo`.
  static const String version = '2.4';

  /// Default protocol scheme.
  static const String protocolScheme = 'https';

  /// Deep-link URL scheme for local transfers.
  static const String scheme = 'bishare';

  // Code generation.
  /// Room-code charset (no I, O, 0, 1).
  static const String codeCharset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int roomCodeLength = 4;

  // Limits.
  static const int maxReceivedFilesInMemory = 100;
  static const int clipboardHistoryMax = 20;
  static const Duration clipboardPollInterval = Duration(milliseconds: 1500);

  /// Accept/reject dialog timeout — the receiver auto-rejects after this.
  static const Duration acceptRejectTimeout = Duration(seconds: 30);

  /// A discovered device is considered stale after this long without being seen.
  static const Duration staleDeviceTimeout = Duration(seconds: 15);

  // Parallel transfer.
  static const int defaultMaxConcurrent = 4;
  static const int defaultMaxConcurrentV2 = 8;

  // Version negotiation gates.
  static const String binaryProtocolMinVersion = '2.1';
  static const String speedProtocolMinVersion = '2.2';
  static const String p2pProtocolMinVersion = '2.3';
  // v2.4 premium-feature gates. Frames 0x0C+ / new fields must never reach a
  // peer below these (old decoders drop the connection on an unknown byte) —
  // gate every emission via PeerCapabilities, not by version string alone.
  static const String syncProtocolMinVersion = '2.4';
  static const String broadcastProtocolMinVersion = '2.4';
  static const String mediaProtocolMinVersion = '2.4';
  static const String clipboardBinaryMinVersion = '2.4';
  static const String resumeOffsetMinVersion = '2.4';

  // Chunking (v2.2 speed protocol). 1 MB chunks (was 256 KB) → 4× fewer per-chunk
  // AES-GCM/FFI/framing ops on the (main-isolate) crypto path, lifting encrypted
  // TCP throughput. Receivers accept up to [maxChunkSize].
  static const int defaultChunkSize = 1024 * 1024;
  static const int minChunkSize = 64 * 1024;
  static const int maxChunkSize = 2 * 1024 * 1024;
  static const int defaultWindowSize = 16;
  static const int defaultStreamsPerFile = 4;

  // Compression.
  static const int compressionMinSize = 1024;
  static const Set<String> compressibleMimeTypes = {
    'text/',
    'application/json',
    'application/xml',
    'application/javascript',
    'application/x-yaml',
    'application/svg+xml',
    'application/xhtml+xml',
  };

  static bool isCompressible(String mimeType) =>
      compressibleMimeTypes.any((p) => mimeType.startsWith(p) || mimeType == p);

  /// Compares two dotted protocol versions (e.g. "2.3" >= "2.2").
  static bool versionAtLeast(String version, String minimum) {
    final v = version.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final m = minimum.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < m.length; i++) {
      final a = i < v.length ? v[i] : 0;
      if (a != m[i]) return a > m[i];
    }
    return true;
  }
}

/// E2E encryption constants (Curve25519 + HKDF-SHA256 + AES-256-GCM).
class BIShareCrypto {
  BIShareCrypto._();

  /// HKDF salt for local E2E file transfer.
  static const String e2eSalt = 'BIShare-E2E';

  /// HKDF info for local E2E file transfer.
  static const String e2eInfo = 'file-transfer';

  /// AES key size in bytes (256 bits).
  static const int aesKeySize = 32;

  /// GCM nonce size in bytes.
  static const int gcmNonceSize = 12;

  /// GCM authentication tag size in bytes (128 bits).
  static const int gcmTagBytes = 16;

  /// SHA-256 bytes used for the visual key fingerprint.
  static const int fingerprintBytes = 8;

  /// GCM overhead per encrypted chunk: nonce(12) + tag(16).
  static const int gcmOverheadPerChunk = gcmNonceSize + gcmTagBytes;
}

/// HTTP status codes with BIShare-specific meaning (see native README table).
class BIShareStatus {
  BIShareStatus._();

  static const int ok = 200;
  static const int badRequest = 400; // malformed client input (e.g. bad upload id)
  static const int pinRequired = 401;
  static const int forbidden = 403; // wrong PIN / rejected / hidden
  static const int notFound = 404; // session or file not found
  static const int busy = 409; // another transfer active
  static const int serverError = 500;
}
