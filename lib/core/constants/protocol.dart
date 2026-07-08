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

  /// QUIC transport + clipboard sync — UDP.
  static const int quic = 58318;

  /// Transfer Rooms — TCP HTTP.
  static const int room = 58319;

  /// WebDAV server — TCP.
  static const int webdav = 58320;
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
  static const String version = '2.3';

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
  static const int pinRequired = 401;
  static const int forbidden = 403; // wrong PIN / rejected / hidden
  static const int notFound = 404; // session or file not found
  static const int busy = 409; // another transfer active
  static const int serverError = 500;
}
