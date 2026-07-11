import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';

typedef ProgressCb = void Function(int received, int total);

/// A user-facing failure while downloading a remote link.
class CloudDownloadException implements Exception {
  const CloudDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns any download/transfer error into a specific, honest message — so the
/// UI never shows a misleading "check your connection" for a 404/410/server
/// error or a file-write failure.
String describeDownloadError(Object e) {
  if (e is CloudDownloadException) return e.message;
  if (e is DioException) {
    final status = e.response?.statusCode;
    if (status == 404) return 'Not found — the link may have expired.';
    if (status == 410) return 'This transfer was already downloaded.';
    if (status == 403) return 'Access denied for this link.';
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Can\'t reach the server. Check your internet connection.';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The connection timed out. Please try again.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed (certificate).';
      case DioExceptionType.badResponse:
        return 'Server error (${status ?? '?'}). Please try again.';
      case DioExceptionType.cancel:
        return 'Cancelled.';
      case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
        return 'Download failed: ${e.message ?? e.error ?? 'unknown error'}';
    }
  }
  return 'Download failed: $e';
}

/// The result of a 24h cloud transfer upload — everything needed to present a
/// shareable link + QR and (later) revoke it.
class CloudUploadResult {
  const CloudUploadResult({
    required this.code,
    required this.rawCode,
    required this.deleteToken,
    this.expiresAt,
    this.oneTime = true,
  });

  /// Human code, e.g. `ABC-DEF`.
  final String code;

  /// Undashed code used in the URL, e.g. `ABCDEF`.
  final String rawCode;
  final String deleteToken;
  final DateTime? expiresAt;
  final bool oneTime;

  /// The canonical share URL (encoded into the QR).
  String get url => CloudConfig.transferWebUrl(rawCode);
}

/// Downloads remote links (24h cloud transfers, user share-links, direct LAN
/// instant URLs) into the app's save directory and records them in the Inbox /
/// History — so a scanned QR or opened universal link lands like any received
/// file. Grounded to the Cloudflare Workers endpoints in [CloudConfig].
class CloudTransferService {
  CloudTransferService(this._server, this._history);

  final TransferServer _server;
  final HistoryRepository _history;
  final Dio _dio = Dio(
    BaseOptions(
      // Large transfers stream for a while; don't time out mid-download.
      receiveTimeout: Duration.zero,
      sendTimeout: Duration.zero,
      followRedirects: true,
    ),
  );

  /// `https://bishare.app/transfer/<code>` — a 24h one-time cloud transfer.
  Future<ReceivedFile> downloadTransfer(
    String code, {
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final meta = _data(
      await _dio.getUri<Map<String, dynamic>>(
        _api(CloudConfig.transferStatus(code)),
      ),
    );
    if (meta == null) throw const CloudDownloadException('Transfer not found');
    if (meta['isDownloaded'] == true) {
      throw const CloudDownloadException('This transfer was already downloaded');
    }
    final fileName = (meta['fileName'] as String?)?.trim();
    final target = await _target(
      fileName == null || fileName.isEmpty ? 'transfer' : fileName,
    );
    await _dio.downloadUri(
      _api(CloudConfig.transferDownload(code)),
      target.path,
      onReceiveProgress: onProgress,
      cancelToken: cancel,
    );
    return _record(
      target,
      meta['mimeType'] as String?,
      (meta['senderAlias'] as String?) ?? 'Cloud transfer',
    );
  }

  /// `https://bishare.app/share/<token>` — an authenticated user share-link.
  /// The server returns a presigned URL, which we then stream.
  Future<ReceivedFile> downloadShare(
    String token, {
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final info = _data(
      await _dio.getUri<Map<String, dynamic>>(_api(CloudConfig.shareInfo(token))),
    );
    if (info == null) throw const CloudDownloadException('Link not found');
    if (info['is_expired'] == true) {
      throw const CloudDownloadException('This link has expired');
    }
    if (info['has_password'] == true) {
      throw const CloudDownloadException('This link is password-protected');
    }
    final fileName = (info['file_name'] as String?)?.trim();
    final resolved = _data(
      await _dio.getUri<Map<String, dynamic>>(
        _api(CloudConfig.shareDownload(token)),
      ),
    );
    final url = resolved?['download_url'] as String?;
    if (url == null) throw const CloudDownloadException('Download unavailable');
    final target = await _target(
      fileName == null || fileName.isEmpty ? 'shared-file' : fileName,
    );
    await _dio.download(
      url,
      target.path,
      onReceiveProgress: onProgress,
      cancelToken: cancel,
    );
    return _record(target, info['mime_type'] as String?, 'Cloud share');
  }

  /// A direct device instant-share URL (`bishare://download` or a raw
  /// `.../api/v1/instant?token=…`). The filename comes from Content-Disposition.
  Future<ReceivedFile> downloadDirect(
    Uri url, {
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final tmp = File(
      '${_server.saveDirectory.path}${Platform.pathSeparator}.bishare-dl-${DateTime.now().microsecondsSinceEpoch}',
    );
    final res = await _dio.downloadUri(
      url,
      tmp.path,
      onReceiveProgress: onProgress,
      cancelToken: cancel,
    );
    final name = _filenameFromDisposition(
      res.headers.value('content-disposition'),
    );
    final target = await _target(name ?? 'file');
    await tmp.rename(target.path);
    return _record(target, res.headers.value(Headers.contentTypeHeader), 'Nearby device');
  }

  /// Upload [file] as a 24h one-time cloud transfer, the off-LAN "web share"
  /// path. Prefers the presigned direct-to-R2 flow (no Worker body-size cap, so
  /// files >200MB work); falls back to the legacy raw-body upload when the
  /// server doesn't have the endpoint yet. Returns the shareable code/URL.
  Future<CloudUploadResult> uploadTransfer({
    required File file,
    required String fileName,
    required String mimeType,
    required String senderAlias,
    bool oneTime = true,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final length = await file.length();

    Map<String, dynamic>? meta;
    try {
      final res = await _dio.postUri<Map<String, dynamic>>(
        _api(CloudConfig.transferUploadUrl),
        data: {
          'name': fileName,
          'size': length,
          'mime_type': mimeType,
          'sender_alias': senderAlias,
          'one_time': oneTime,
        },
        cancelToken: cancel,
      );
      meta = res.data;
    } on DioException catch (e) {
      // 404/405 = older server without /upload-url — use the legacy path.
      final status = e.response?.statusCode;
      if (status != 404 && status != 405) rethrow;
    }

    final uploadUrl = meta?['uploadUrl'] as String?;
    if (meta == null || uploadUrl == null) {
      return _uploadTransferLegacy(
        file: file,
        fileName: fileName,
        mimeType: mimeType,
        senderAlias: senderAlias,
        length: length,
        oneTime: oneTime,
        onProgress: onProgress,
        cancel: cancel,
      );
    }

    // Direct PUT to R2. Content-Type must match the presigned signature.
    await _dio.put<void>(
      uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          Headers.contentLengthHeader: length,
          Headers.contentTypeHeader:
              (meta['uploadHeaders'] as Map<String, dynamic>?)?['Content-Type'] as String? ?? mimeType,
        },
      ),
      onSendProgress: onProgress,
      cancelToken: cancel,
    );
    return _uploadResult(meta, oneTime);
  }

  /// Legacy raw-body upload through the Worker (caps out at the Cloudflare
  /// edge body limit; kept for servers without the presigned endpoint).
  Future<CloudUploadResult> _uploadTransferLegacy({
    required File file,
    required String fileName,
    required String mimeType,
    required String senderAlias,
    required int length,
    required bool oneTime,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final res = await _dio.postUri<Map<String, dynamic>>(
      _api(CloudConfig.transferUpload),
      data: file.openRead(),
      options: Options(
        headers: {
          'X-File-Name': fileName,
          'X-File-Type': mimeType,
          'X-Sender-Alias': senderAlias,
          if (oneTime) 'X-One-Time': 'true',
          Headers.contentLengthHeader: length,
        },
        contentType: 'application/octet-stream',
      ),
      onSendProgress: onProgress,
      cancelToken: cancel,
    );
    return _uploadResult(res.data, oneTime);
  }

  /// Both upload flows return the same flat body:
  /// {success, code, rawCode, expiresAt, deleteToken, ...}.
  CloudUploadResult _uploadResult(Map<String, dynamic>? body, bool oneTime) {
    final code = body?['code'] as String?;
    final rawCode = body?['rawCode'] as String?;
    if (code == null || rawCode == null) {
      throw const CloudDownloadException('Upload failed. Please try again.');
    }
    return CloudUploadResult(
      code: code,
      rawCode: rawCode,
      deleteToken: (body?['deleteToken'] as String?) ?? '',
      expiresAt: DateTime.tryParse(body?['expiresAt'] as String? ?? ''),
      oneTime: oneTime,
    );
  }

  // ---- helpers ----

  Uri _api(String path) => Uri.parse('${CloudConfig.apiBase}$path');

  /// Unwraps the `{success, data}` envelope; tolerates flat bodies.
  Map<String, dynamic>? _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    if (body == null) return null;
    final inner = body['data'];
    if (inner is Map<String, dynamic>) return inner;
    return body;
  }

  Future<ReceivedFile> _record(File file, String? mime, String sender) async {
    final size = await file.length();
    final received = ReceivedFile(
      fileName: file.uri.pathSegments.last,
      savedPath: file.path,
      size: size,
      senderAlias: sender,
      receivedAt: DateTime.now(),
      verified: false,
      fileType: mime,
      encrypted: false,
    );
    await _history.recordReceived(received);
    return received;
  }

  /// A collision-free path in the save directory for [fileName]. The chosen
  /// name is **reserved immediately** (a zero-byte placeholder) so two
  /// concurrent downloads can never resolve to the same path (TOCTOU-safe).
  Future<File> _target(String fileName) async {
    final dir = _server.saveDirectory;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = _sanitize(fileName);
    final dot = safe.lastIndexOf('.');
    final stem = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    var candidate = safe;
    var n = 1;
    while (true) {
      final file = File('${dir.path}${Platform.pathSeparator}$candidate');
      try {
        file.createSync(exclusive: true); // atomic reserve
        return file;
      } on FileSystemException {
        candidate = '$stem ($n)$ext';
        n++;
      }
    }
  }

  static String _sanitize(String name) {
    final base = name.split(RegExp(r'[/\\]')).last.trim();
    final cleaned = base.replaceAll(RegExp(r'[\x00-\x1f]'), '');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  static String? _filenameFromDisposition(String? header) {
    if (header == null) return null;
    final star = RegExp("filename\\*=(?:UTF-8'')?([^;]+)", caseSensitive: false)
        .firstMatch(header);
    if (star != null) {
      return Uri.decodeComponent(star.group(1)!.trim().replaceAll('"', ''));
    }
    final plain = RegExp('filename="?([^";]+)"?', caseSensitive: false)
        .firstMatch(header);
    return plain?.group(1)?.trim();
  }
}
