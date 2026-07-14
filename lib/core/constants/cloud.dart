/// Cloud + universal-link endpoints for BIShare's remote features (rooms,
/// stream-relay, 24h cloud transfer, share links). These mirror the native
/// iOS client's `AppSettings.cloudBaseURL` / universal-link host so links and
/// QR codes interoperate cross-platform.
library;

class CloudConfig {
  CloudConfig._();

  /// REST + WebSocket API host (Cloudflare Workers).
  static const String apiBase = 'https://api.bishare.app';

  /// WebSocket base (rooms + stream relay).
  static const String wsBase = 'wss://api.bishare.app';

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

  // ---- Auth (magic-link + OAuth google/apple) — §B ----
  /// Request a 6-char sign-in code by email (`{email}` → 200 `{message,expires_in}`).
  static const String authMagicLink = '/api/v1/auth/magic-link';

  /// Exchange `{email,code[,device_name,device_id]}` for `{access_token,refresh_token,user}`.
  static const String authMagicLinkVerify = '/api/v1/auth/magic-link/verify';

  /// Exchange a provider `{provider,id_token[,name,device_name,device_id]}` for the
  /// SAME `{access_token,refresh_token,user}` envelope as magic-link verify.
  static const String authOauth = '/api/v1/auth/oauth';

  /// Rotate an access token: `{refresh_token}` → `{access_token[,refresh_token]}`.
  static const String authRefresh = '/api/v1/auth/refresh';

  /// Best-effort refresh-token revoke (Bearer access token required).
  static const String authLogout = '/api/v1/auth/logout';

  /// Current user (Bearer): GET reads, PATCH updates, DELETE soft-deletes.
  /// Consumed by Fase B (Drive) via the authenticated Dio.
  static const String userMe = '/api/v1/user/me';

  // ---- Drive: storage + folders + files + shares (§C/§D/§E, Bearer) ----
  /// Storage quota + by-type breakdown (`{total,used,limit,tier,used_percent,by_type}`).
  static const String storageUsage = '/api/v1/storage/usage';

  /// 20 most-recent files (bare array).
  static const String storageRecent = '/api/v1/storage/recent';

  /// Folders: `GET ?parent_id` lists children (root when absent); `POST` creates.
  static const String folders = '/api/v1/folders';
  static String folder(String id) => '/api/v1/folders/$id';

  /// Root-first ancestor chain of a folder.
  static String folderBreadcrumb(String id) => '/api/v1/folders/$id/breadcrumb';

  /// Files: `GET` (paginated `?folder_id&page&per_page&sort&order`) / trash / etc.
  static const String files = '/api/v1/files';
  static const String filesTrash = '/api/v1/files/trash';

  /// Small (<=50 MiB) presigned upload: url → PUT R2 → confirm.
  static const String filesUploadUrl = '/api/v1/files/upload-url';
  static const String filesConfirmUpload = '/api/v1/files/confirm-upload';

  /// Large (>50 MiB) multipart upload: init → PUT parts → complete.
  static const String filesMultipartInit = '/api/v1/files/multipart/init';
  static const String filesMultipartComplete =
      '/api/v1/files/multipart/complete';

  static String file(String id) => '/api/v1/files/$id';
  static String fileDownloadUrl(String id) => '/api/v1/files/$id/download-url';
  static String filePermanent(String id) => '/api/v1/files/$id/permanent';
  static String fileRestore(String id) => '/api/v1/files/$id/restore';

  /// Authenticated share-links: `POST` create, `GET` list, `DELETE :id` revoke.
  static const String shares = '/api/v1/shares';
  static String share(String id) => '/api/v1/shares/$id';

  // ---- REST paths (relative to [apiBase]) ----
  /// Server config: tier limits at `data.limits.transfer_max_file_size_*`.
  static const String config = '/api/v1/config';

  /// 24h one-time cloud transfer upload (raw body + `X-File-Name` headers).
  static const String transferUpload = '/api/v1/transfer/upload';

  /// Presigned direct-to-R2 upload (bypasses the Worker body cap; >200MB ok).
  static const String transferUploadUrl = '/api/v1/transfer/upload-url';
  static String transferDownload(String code) => '/api/v1/transfer/download/$code';
  static String transferStatus(String code) => '/api/v1/transfer/status/$code';
  static String transferDelete(String code) => '/api/v1/transfer/delete/$code';

  /// Authenticated user share-links (public read at `/s/<token>`).
  static String shareInfo(String token) => '/s/$token';
  static String shareVerify(String token) => '/s/$token/verify';
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
