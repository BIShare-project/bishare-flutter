import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/crypto/bse2.dart';
import '../../../core/io/scratch_dir.dart';
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

/// The looked-up 24h transfer does not exist (404 / empty status body). A
/// dedicated type so callers can tell "no such stored transfer" (e.g. to fall
/// back to a live stream) apart from other download failures without matching
/// on the message text — the two sites can't silently drift.
class TransferNotFoundException extends CloudDownloadException {
  const TransferNotFoundException() : super('Transfer not found');
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
    // Upload rate or daily volume limit for this network — not a server fault,
    // and "try again" right away would fail the same way.
    if (status == 429) {
      return 'Too many uploads from this network right now. Please try again later.';
    }
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
    this.key,
  });

  /// Human code, e.g. `ABC-DEF`.
  final String code;

  /// Undashed code used in the URL, e.g. `ABCDEF`.
  final String rawCode;
  final String deleteToken;
  final DateTime? expiresAt;
  final bool oneTime;

  /// The end-to-end key (base64url) when the upload was sealed as a BSE2
  /// container, else null. It lives ONLY in the link fragment below — never
  /// in the code, never on the server — so the 6-character code alone cannot
  /// open an encrypted transfer.
  final String? key;

  bool get encrypted => key != null;

  /// The canonical share URL (encoded into the QR). For an encrypted upload it
  /// carries the key after `#`, which browsers never send to any server.
  String get url {
    final base = CloudConfig.transferWebUrl(rawCode);
    return key == null ? base : '$base#k=$key';
  }
}

/// Downloads remote links (24h cloud transfers, user share-links, direct LAN
/// instant URLs) into the app's save directory and records them in the Inbox /
/// History — so a scanned QR or opened universal link lands like any received
/// file. Grounded to the Cloudflare Workers endpoints in [CloudConfig].
class CloudTransferService {
  CloudTransferService(
    this._server,
    this._history, {
    String? apiBase,
    int? multipartThreshold,
  }) : _apiBase = apiBase ?? CloudConfig.apiBase,
       _multipartThreshold = multipartThreshold ?? defaultMultipartThreshold;

  final TransferServer _server;
  final HistoryRepository _history;

  /// Overridable so a test can point the real upload flow at a local server.
  final String _apiBase;

  /// Bodies above this go up as resumable multipart — one presigned PUT per
  /// 50 MiB part, retried and re-presigned per part. Below it, a single
  /// presigned PUT. The threshold matters for more than speed: a single R2
  /// PUT is capped at 5 GiB, so without multipart the app could accept a
  /// large file, seal it, and fail at the very end. Mirrors the web client.
  /// Injectable so tests can exercise multipart with small files.
  final int _multipartThreshold;
  static const int defaultMultipartThreshold = 100 * 1024 * 1024;

  /// Per-part attempts before the whole upload fails. A failed attempt drops
  /// the cached URL so the retry gets a fresh presign in case it expired.
  static const int _partRetries = 3;
  final Dio _dio = Dio(
    BaseOptions(
      // Large transfers stream for a while; don't time out mid-download.
      receiveTimeout: Duration.zero,
      sendTimeout: Duration.zero,
      followRedirects: true,
    ),
  );

  /// `https://bishare.app/transfer/<code>` — a 24h one-time cloud transfer.
  ///
  /// Web uploads are end-to-end encrypted by default (the "BSE2" container;
  /// see [Bse2]): the stored blob is ciphertext and [key] — the link's `#k=`
  /// fragment, carried by the QR/universal link but never sent to any server —
  /// is required to decrypt it. A hand-typed code has no key, so an encrypted
  /// transfer is surfaced honestly instead of saving unreadable bytes.
  Future<ReceivedFile> downloadTransfer(
    String code, {
    String? key,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    Response<Map<String, dynamic>> statusRes;
    try {
      statusRes = await _dio.getUri<Map<String, dynamic>>(
        _api(CloudConfig.transferStatus(code)),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const TransferNotFoundException();
      }
      rethrow;
    }
    final meta = _data(statusRes);
    if (meta == null) throw const TransferNotFoundException();
    if (meta['isDownloaded'] == true) {
      throw const CloudDownloadException(
        'This transfer was already downloaded',
      );
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
    final wasEncrypted = await _decryptIfBse2(target, key);
    return _record(
      target,
      meta['mimeType'] as String?,
      (meta['senderAlias'] as String?) ?? 'Cloud transfer',
      encrypted: wasEncrypted,
    );
  }

  /// If [target] is a BSE2 container (an end-to-end-encrypted web upload),
  /// decrypt it in place using the link-fragment [key]. Returns whether the
  /// blob was encrypted. Without a valid key the unreadable blob is deleted
  /// and an honest error is thrown — never silently keep ciphertext.
  Future<bool> _decryptIfBse2(File target, String? key) async {
    if (!await Bse2.sniff(target)) return false;
    final raw = key == null ? null : Bse2.decodeKey(key);
    if (raw == null) {
      await target.delete();
      throw CloudDownloadException('remote.encrypted_needs_link'.tr());
    }
    final plain = File('${target.path}.bse2-plain');
    try {
      await Bse2.decryptFile(input: target, output: plain, key: raw);
    } on Bse2Exception {
      if (await plain.exists()) await plain.delete();
      await target.delete();
      throw CloudDownloadException('remote.encrypted_bad_key'.tr());
    }
    await target.delete();
    await plain.rename(target.path);
    return true;
  }

  /// `https://bishare.app/share/<token>` — an authenticated user share-link.
  /// The server returns a presigned URL, which we then stream.
  Future<ReceivedFile> downloadShare(
    String token, {
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final info = _data(
      await _dio.getUri<Map<String, dynamic>>(
        _api(CloudConfig.shareInfo(token)),
      ),
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

  /// A direct URL download (a device instant-share `bishare://download`, a raw
  /// `.../api/v1/instant?token=…`, or a presigned Drive `download-url`). The
  /// filename comes from Content-Disposition; [senderLabel] tags the Inbox row.
  Future<ReceivedFile> downloadDirect(
    Uri url, {
    ProgressCb? onProgress,
    CancelToken? cancel,
    String senderLabel = 'Nearby device',
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
    return _record(
      target,
      res.headers.value(Headers.contentTypeHeader),
      senderLabel,
    );
  }

  /// Upload [file] as a 24h one-time cloud transfer, the off-LAN "web share"
  /// path. Prefers the presigned direct-to-R2 flow (no Worker body-size cap, so
  /// files >200MB work); falls back to the legacy raw-body upload when the
  /// server doesn't have the endpoint yet. Returns the shareable code/URL.
  ///
  /// **End-to-end encrypted by default**, exactly like the web client: the file
  /// is sealed into a BSE2 container (shared Rust code — see [Bse2]) in a
  /// scratch file, ONLY that ciphertext is uploaded (the server is told the
  /// ciphertext size, since that is what it stores), and the 32-byte key rides
  /// in the returned link's `#k=` fragment, which browsers never send to a
  /// server. The relay therefore stores bytes it cannot read. The scratch file
  /// is removed whether or not the upload succeeds. [onEncryptProgress]
  /// reports the sealing pass (plaintext bytes done / total) before
  /// [onProgress] reports upload bytes.
  Future<CloudUploadResult> uploadTransfer({
    required File file,
    required String fileName,
    required String mimeType,
    required String senderAlias,
    bool oneTime = true,
    bool encrypt = true,
    ProgressCb? onEncryptProgress,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    Directory? scratch;
    var body = file;
    String? keyFragment;
    try {
      if (encrypt) {
        final raw = Bse2.generateKey();
        keyFragment = Bse2.encodeKey(raw);
        scratch = await createScratchDir('bishare-e2e-');
        body = File('${scratch.path}${Platform.pathSeparator}upload.bse2');
        await Bse2.encryptFile(
          input: file,
          output: body,
          key: raw,
          onProgress: onEncryptProgress,
        );
      }
      return await _uploadBody(
        body: body,
        fileName: fileName,
        mimeType: mimeType,
        senderAlias: senderAlias,
        oneTime: oneTime,
        key: keyFragment,
        onProgress: onProgress,
        cancel: cancel,
      );
    } finally {
      if (scratch != null) {
        try {
          await scratch.delete(recursive: true);
        } on Object {
          // Best effort: the OS reclaims its temp dir anyway.
        }
      }
    }
  }

  /// The wire part of [uploadTransfer]: [body] is exactly what the relay will
  /// store (ciphertext when sealed, the file itself otherwise).
  Future<CloudUploadResult> _uploadBody({
    required File body,
    required String fileName,
    required String mimeType,
    required String senderAlias,
    required bool oneTime,
    required String? key,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final file = body;
    final length = await file.length();

    if (length > _multipartThreshold) {
      return _uploadMultipart(
        body: file,
        length: length,
        fileName: fileName,
        mimeType: mimeType,
        senderAlias: senderAlias,
        oneTime: oneTime,
        key: key,
        onProgress: onProgress,
        cancel: cancel,
      );
    }

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
        key: key,
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
              (meta['uploadHeaders'] as Map<String, dynamic>?)?['Content-Type']
                  as String? ??
              mimeType,
        },
      ),
      onSendProgress: onProgress,
      cancelToken: cancel,
    );
    return _uploadResult(meta, oneTime, key: key);
  }

  /// Resumable multipart: the server presigns every part up front; each part
  /// is PUT straight to R2 from a slice of [body], retried per part with a
  /// fresh presign on failure; then `complete` assembles the object (the
  /// server reads the part list itself and measures the result) and returns
  /// the same flat code/URL body as the single-PUT flow.
  Future<CloudUploadResult> _uploadMultipart({
    required File body,
    required int length,
    required String fileName,
    required String mimeType,
    required String senderAlias,
    required bool oneTime,
    required String? key,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final init = await _dio.postUri<Map<String, dynamic>>(
      _api(CloudConfig.transferMultipartInit),
      data: {'name': fileName, 'size': length, 'mime_type': mimeType},
      cancelToken: cancel,
    );
    final meta = init.data;
    final uploadId = meta?['uploadId'] as String?;
    final storageKey = meta?['storageKey'] as String?;
    final partSize = (meta?['partSize'] as num?)?.toInt();
    final totalParts = (meta?['totalParts'] as num?)?.toInt();
    if (uploadId == null ||
        storageKey == null ||
        partSize == null ||
        partSize <= 0 ||
        totalParts == null ||
        totalParts < 1) {
      throw const CloudDownloadException('Upload failed. Please try again.');
    }
    final urls = <int, String>{};
    for (final p in (meta?['parts'] as List?) ?? const []) {
      if (p is Map) {
        final n = (p['part_number'] as num?)?.toInt();
        final u = p['upload_url'] as String?;
        if (n != null && u != null) urls[n] = u;
      }
    }

    Future<String> urlFor(int part) async {
      final cached = urls[part];
      if (cached != null) return cached;
      final res = await _dio.postUri<Map<String, dynamic>>(
        _api(CloudConfig.transferMultipartPartUrls),
        data: {
          'uploadId': uploadId,
          'storageKey': storageKey,
          'partNumbers': [part],
        },
        cancelToken: cancel,
      );
      final list = res.data?['parts'] as List?;
      final fresh = list != null && list.isNotEmpty
          ? (list.first as Map)['upload_url'] as String?
          : null;
      if (fresh == null) {
        throw const CloudDownloadException('Upload failed. Please try again.');
      }
      urls[part] = fresh;
      return fresh;
    }

    // From here on the upload exists on R2 and only this call can finish it:
    // its state lives in memory, so whatever stops it — the user, the network,
    // the server — the parts must be freed rather than left for the sweep.
    try {
      var doneBytes = 0;
      for (var part = 1; part <= totalParts; part++) {
        final start = (part - 1) * partSize;
        final end = min(start + partSize, length);
        final partLength = end - start;
        for (var attempt = 0; ; attempt++) {
          try {
            final url = await urlFor(part);
            // A fresh stream per attempt; the slice is re-read from disk on
            // retry. No Content-Type: part URLs are not signed for one (as on
            // the web).
            await _dio.put<void>(
              url,
              data: body.openRead(start, end),
              options: Options(
                headers: {Headers.contentLengthHeader: partLength},
              ),
              onSendProgress: (sent, _) =>
                  onProgress?.call(doneBytes + sent, length),
              cancelToken: cancel,
            );
            break;
          } on DioException catch (e) {
            if (CancelToken.isCancel(e) || attempt >= _partRetries) rethrow;
            urls.remove(part); // force a fresh presign in case the URL expired
          }
        }
        doneBytes += partLength;
        onProgress?.call(doneBytes, length);
      }

      final done = await _dio.postUri<Map<String, dynamic>>(
        _api(CloudConfig.transferMultipartComplete),
        data: {
          'uploadId': uploadId,
          'storageKey': storageKey,
          'name': fileName,
          'size': length,
          'mime_type': mimeType,
          'sender_alias': senderAlias,
          'one_time': oneTime,
        },
        cancelToken: cancel,
      );
      return _uploadResult(done.data, oneTime, key: key);
    } on Object {
      await _abortMultipart(uploadId, storageKey);
      rethrow;
    }
  }

  /// Best-effort `multipart/abort`: R2 drops the parts now instead of at the
  /// server's 24 h sweep. Never throws, never uses the caller's cancel token
  /// (it is usually the reason we are here), and gives up quickly — the sweep
  /// is the backstop if this doesn't get through. Harmless when `complete`
  /// already assembled or aborted the upload server-side.
  Future<void> _abortMultipart(String uploadId, String storageKey) async {
    try {
      await _dio
          .postUri<void>(
            _api(CloudConfig.transferMultipartAbort),
            data: {'uploadId': uploadId, 'storageKey': storageKey},
            options: Options(
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            ),
          )
          .timeout(const Duration(seconds: 15));
    } on Object {
      // Best effort — see above.
    }
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
    required String? key,
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
    return _uploadResult(res.data, oneTime, key: key);
  }

  /// Both upload flows return the same flat body:
  /// {success, code, rawCode, expiresAt, deleteToken, ...}.
  CloudUploadResult _uploadResult(
    Map<String, dynamic>? body,
    bool oneTime, {
    required String? key,
  }) {
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
      key: key,
    );
  }

  // ---- helpers ----

  Uri _api(String path) => Uri.parse('$_apiBase$path');

  /// Unwraps the `{success, data}` envelope; tolerates flat bodies.
  Map<String, dynamic>? _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    if (body == null) return null;
    final inner = body['data'];
    if (inner is Map<String, dynamic>) return inner;
    return body;
  }

  Future<ReceivedFile> _record(
    File file,
    String? mime,
    String sender, {
    bool encrypted = false,
  }) async {
    final size = await file.length();
    final received = ReceivedFile(
      fileName: file.uri.pathSegments.last,
      savedPath: file.path,
      size: size,
      senderAlias: sender,
      receivedAt: DateTime.now(),
      verified: false,
      fileType: mime,
      encrypted: encrypted,
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
    final star = RegExp(
      "filename\\*=(?:UTF-8'')?([^;]+)",
      caseSensitive: false,
    ).firstMatch(header);
    if (star != null) {
      return Uri.decodeComponent(star.group(1)!.trim().replaceAll('"', ''));
    }
    final plain = RegExp(
      'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(header);
    return plain?.group(1)?.trim();
  }
}
