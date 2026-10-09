/// Cloud + universal-link endpoints for BIShare's remote features (rooms,
/// stream-relay, 24h cloud transfer, share links). These mirror the native
/// iOS client's `AppSettings.cloudBaseURL` / universal-link host so links and
/// QR codes interoperate cross-platform.
library;

class CloudConfig {
  CloudConfig._();

  /// REST + WebSocket API host (Cloudflare Workers). Overridable only at
  /// compile time, for tests against a local worker
  /// (`--dart-define=BISHARE_API_BASE=http://localhost:8799`).
  static const String apiBase = String.fromEnvironment(
    'BISHARE_API_BASE',
    defaultValue: 'https://api.bishare.app',
  );

  /// WebSocket base (rooms + stream relay).
  static const String wsBase = String.fromEnvironment(
    'BISHARE_WS_BASE',
    defaultValue: 'wss://api.bishare.app',
  );

  /// Web host used in universal links / QR codes (`/transfer`, `/share`, …).
  static const String webBase = 'https://bishare.app';

  /// Universal-link host (no scheme) for app-links association + parsing.
  static const String webHost = 'bishare.app';

  // Custom URL schemes registered on the app (see Info.plist / AndroidManifest).
  /// Local transfers + share intents (`bishare://share`, `bishare://download`).
  static const String scheme = 'bishare';

  /// Remote stream-relay receive (`bishare-remote://<code>`).
  static const String schemeRemote = 'bishare-remote';

  /// Remote stream-relay receive (`bishare-stream://<code>`).
  static const String schemeStream = 'bishare-stream';

  // ---- Folder sync: cloud endpoints (Bearer) ----
  /// Content dedup: `{hashes:[sha256…]}` (1–500, lowercase hex) → exists map.
  /// Folder-sync M3 checks CIPHERTEXT hashes here (idempotent re-push, §7.1).
  static const String filesCheckExists = '/api/v1/files/check-exists';

  /// Cheap change beacon: `{last_sync_at,total_files,total_size,…}` — the
  /// fingerprint triple folder-sync polls to know "pull the manifest" (§5.2).
  static const String filesSyncStatus = '/api/v1/files/sync-status';

  // ---- REST paths (relative to [apiBase]) ----
  /// Server config: tier limits at `data.limits.transfer_max_file_size_*`.
  static const String config = '/api/v1/config';

  /// 24h one-time cloud transfer upload (raw body + `X-File-Name` headers).
  static const String transferUpload = '/api/v1/transfer/upload';

  /// Presigned direct-to-R2 upload (bypasses the Worker body cap; >200MB ok).
  static const String transferUploadUrl = '/api/v1/transfer/upload-url';

  /// Resumable multipart (bodies above the client threshold): init → one
  /// presigned PUT per 50 MiB part → complete. Same machinery the web uses.
  static const String transferMultipartInit = '/api/v1/transfer/multipart/init';
  static const String transferMultipartPartUrls =
      '/api/v1/transfer/multipart/part-urls';
  static const String transferMultipartComplete =
      '/api/v1/transfer/multipart/complete';

  /// Frees the parts of a multipart upload that will not be finished
  /// (cancelled or failed) — otherwise they sit on R2 until the server's
  /// 24 h sweep.
  static const String transferMultipartAbort =
      '/api/v1/transfer/multipart/abort';
  static String transferDownload(String code) =>
      '/api/v1/transfer/download/$code';
  static String transferStatus(String code) => '/api/v1/transfer/status/$code';
  static String transferDelete(String code) => '/api/v1/transfer/delete/$code';

  /// Authenticated user share-links (public read at `/s/<token>`).
  static String shareInfo(String token) => '/s/$token';
  static String shareDownload(String token) => '/s/$token/download';

  // ---- Rooms (REST) ----
  static const String rooms = '/api/v1/rooms';
  static String room(String code) => '/api/v1/rooms/$code';
  static String roomJoin(String code) => '/api/v1/rooms/$code/join';
  static String roomInfo(String code) => '/api/v1/rooms/$code/info';
  static String roomMembers(String code) => '/api/v1/rooms/$code/members';
  static String roomFiles(String code) => '/api/v1/rooms/$code/files';
  static String roomFile(String code, String id) =>
      '/api/v1/rooms/$code/files/$id';
  static String roomPing(String code) => '/api/v1/rooms/$code/ping';
  static String roomLeave(String code) => '/api/v1/rooms/$code/leave';
  static String roomSync(String code) => '/api/v1/rooms/$code/sync';

  /// Room WebSocket (presence + broadcasts). Full URL: [wsBase] + this.
  static String roomWs(String code) => '/api/v1/rooms/$code/ws';

  /// Stream-relay WebSocket (zero-storage peer↔peer). Full URL: [wsBase] + this.
  static const String stream = '/api/v1/stream';

  /// Canonical share URL encoded into a QR / copied for a 24h cloud transfer.
  static String transferWebUrl(String rawCode) => '$webBase/transfer/$rawCode';
}

/// Code alphabets + lengths, grounded to the protocol crate + backend. Used to
/// generate and validate room / stream codes identically across platforms.
class ShareCodes {
  ShareCodes._();

  /// Room codes: 4 chars (no I, O, 0, 1). Matches `Config::CODE_CHARSET`.
  static const String roomCharset = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int roomLength = 4;

  /// Stream-relay codes: 6 chars (no I, L, O, 0, 1).
  static const String streamCharset = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int streamLength = 6;
}
