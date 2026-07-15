import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';

import '../../../core/constants/cloud.dart';
import '../domain/drive_models.dart';

typedef ProgressCb = void Function(int sent, int total);

/// A user-facing Drive failure carrying the backend error [code] (e.g.
/// `STORAGE_LIMIT_EXCEEDED`, `FILE_TOO_LARGE`, `DUPLICATE_NAME`) so the
/// presentation layer can localize it, or a synthetic `NETWORK`/`UNKNOWN`.
class DriveException implements Exception {
  const DriveException(this.message, {this.code, this.status});

  final String message;
  final String? code;
  final int? status;

  @override
  String toString() => 'DriveException($code/$status): $message';
}

/// The Drive data layer: browses folders/files, mutates (create/rename/move/
/// delete/trash), reports storage, and runs the presigned upload + download-url
/// flows — all through Fase A's authenticated [Dio] (Bearer + silent refresh).
/// R2 object PUT/GET use a separate bare [Dio] (no auth, no timeouts) so large
/// transfers stream without the Worker body cap, exactly like
/// `CloudTransferService`'s presigned path.
class DriveService {
  DriveService(this._dio);

  /// Fase A's authenticated client (from `AuthedDio.dio`).
  final Dio _dio;

  /// Direct-to-R2 transfers: no base URL, no auth header, no read/write timeout.
  final Dio _r2 = Dio(
    BaseOptions(
      receiveTimeout: Duration.zero,
      sendTimeout: Duration.zero,
      followRedirects: true,
    ),
  );

  /// Files at/above this size use the multipart flow (matches server PART_SIZE).
  static const int multipartThreshold = 50 * 1024 * 1024;
  static const int _partSize = 50 * 1024 * 1024;

  // ---- Browse ---------------------------------------------------------------

  /// Child folders of [parentId] (root folders when null). Ordered name ASC.
  ///
  /// Folder-sync keeps its content-addressed store in hidden
  /// `.bishare-sync-<pairId>` folders (Tahap 4, Q3): the Drive UI filters them
  /// out by default; only the sync engine lists with [includeHidden].
  Future<List<DriveFolder>> folders({
    String? parentId,
    bool includeHidden = false,
  }) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      CloudConfig.folders,
      queryParameters: {'parent_id': ?parentId},
    );
    final data = (res.data?['data'] as List?) ?? const [];
    return [
      for (final f in data)
        if (f is Map<String, dynamic>)
          for (final folder in [DriveFolder.fromJson(f)])
            if (includeHidden || !folder.name.startsWith('.bishare-sync-'))
              folder,
    ];
  });

  /// One page of files in [folderId] (root when null), paginated + sorted.
  Future<DriveFilePage> files({
    String? folderId,
    int page = 1,
    int perPage = 50,
    String sort = 'name',
    String order = 'asc',
  }) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      CloudConfig.files,
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'sort': sort,
        'order': order,
        'folder_id': ?folderId,
      },
    );
    return _filePage(res.data, page);
  });

  /// Trashed files (soft-deleted), paginated + sorted.
  Future<DriveFilePage> trash({
    int page = 1,
    int perPage = 50,
    String sort = 'updated_at',
    String order = 'desc',
  }) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      CloudConfig.filesTrash,
      queryParameters: {
        'page': page,
        'per_page': perPage,
        'sort': sort,
        'order': order,
      },
    );
    return _filePage(res.data, page);
  });

  /// Root-first ancestor chain of [folderId] (target folder last).
  Future<List<DriveFolder>> breadcrumb(String folderId) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      CloudConfig.folderBreadcrumb(folderId),
    );
    final data = (res.data?['data'] as List?) ?? const [];
    return [
      for (final f in data)
        if (f is Map<String, dynamic>) DriveFolder.fromJson(f),
    ];
  });

  /// Storage quota + by-type breakdown.
  Future<StorageUsage> storageUsage() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(CloudConfig.storageUsage);
    return StorageUsage.fromJson(
      (res.data?['data'] as Map<String, dynamic>?) ?? const {},
    );
  });

  /// The 20 most-recently created files (across all folders).
  Future<List<DriveFile>> recent() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(CloudConfig.storageRecent);
    final data = (res.data?['data'] as List?) ?? const [];
    return [
      for (final f in data)
        if (f is Map<String, dynamic>) DriveFile.fromJson(f),
    ];
  });

  // ---- Mutations ------------------------------------------------------------

  Future<DriveFolder> createFolder(String name, {String? parentId}) =>
      _call(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          CloudConfig.folders,
          data: {
            'name': name,
            'parent_id': ?parentId,
          },
        );
        return DriveFolder.fromJson(
          (res.data?['data'] as Map<String, dynamic>?) ?? const {},
        );
      });

  /// PATCH a folder: rename ([name]) and/or move ([parentId], UUID only — the
  /// contract has no "move to root").
  Future<void> updateFolder(String id, {String? name, String? parentId}) =>
      _call(() async {
        await _dio.patch<Map<String, dynamic>>(
          CloudConfig.folder(id),
          data: {
            'name': ?name,
            'parent_id': ?parentId,
          },
        );
      });

  /// PATCH a file: rename ([name]) and/or move ([parentId] → `folder_id`).
  Future<void> updateFile(String id, {String? name, String? parentId}) =>
      _call(() async {
        await _dio.patch<Map<String, dynamic>>(
          CloudConfig.file(id),
          data: {
            'name': ?name,
            'folder_id': ?parentId,
          },
        );
      });

  /// Soft-delete a file (moves to trash).
  Future<void> deleteFile(String id) =>
      _call(() => _dio.delete<Map<String, dynamic>>(CloudConfig.file(id)));

  /// Soft-delete a folder (and, server-side, its direct contents).
  Future<void> deleteFolder(String id) =>
      _call(() => _dio.delete<Map<String, dynamic>>(CloudConfig.folder(id)));

  /// Restore a trashed file.
  Future<void> restoreFile(String id) => _call(
    () => _dio.post<Map<String, dynamic>>(CloudConfig.fileRestore(id)),
  );

  /// Permanently delete a file (from trash or not) — irreversible.
  Future<void> deleteFilePermanent(String id) => _call(
    () => _dio.delete<Map<String, dynamic>>(CloudConfig.filePermanent(id)),
  );

  // ---- Download -------------------------------------------------------------

  /// Resolve a short-lived presigned GET URL for [fileId]. Feed it to
  /// `CloudTransferService.downloadDirect` to stream + record like any download.
  Future<String> downloadUrl(String fileId) => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      CloudConfig.fileDownloadUrl(fileId),
    );
    final url = (res.data?['data'] as Map<String, dynamic>?)?['download_url'];
    if (url is! String || url.isEmpty) {
      throw const DriveException('no download url', code: 'UNKNOWN');
    }
    return url;
  });

  // ---- Upload ---------------------------------------------------------------

  /// Upload [file] into [folderId] (root when null). Picks the small presigned
  /// PUT flow (<=50 MiB) or the S3 multipart flow automatically. [onProgress]
  /// reports bytes sent across the whole file. Returns the created [DriveFile].
  Future<DriveFile> upload(
    File file, {
    String? folderId,
    String? name,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final length = await file.length();
    final fileName = name ?? file.uri.pathSegments.last;
    final mime = lookupMimeType(fileName) ?? 'application/octet-stream';
    if (length >= multipartThreshold) {
      return _uploadMultipart(
        file: file,
        name: fileName,
        mime: mime,
        length: length,
        folderId: folderId,
        onProgress: onProgress,
        cancel: cancel,
      );
    }
    return _uploadSmall(
      file: file,
      name: fileName,
      mime: mime,
      length: length,
      folderId: folderId,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  Future<DriveFile> _uploadSmall({
    required File file,
    required String name,
    required String mime,
    required int length,
    required String? folderId,
    required ProgressCb? onProgress,
    required CancelToken? cancel,
  }) => _call(() async {
    // 1) Reserve quota + presign the PUT.
    final init = await _dio.post<Map<String, dynamic>>(
      CloudConfig.filesUploadUrl,
      data: {
        'name': name,
        'size': length,
        'mime_type': mime,
        'folder_id': ?folderId,
      },
      cancelToken: cancel,
    );
    final meta = init.data?['data'] as Map<String, dynamic>? ?? const {};
    final uploadUrl = meta['upload_url'] as String?;
    final storageKey = meta['storage_key'] as String?;
    final uploadId = meta['upload_id'] as String?;
    if (uploadUrl == null || storageKey == null || uploadId == null) {
      throw const DriveException('bad upload url', code: 'UNKNOWN');
    }
    // 2) PUT straight to R2. Content-Type MUST match the signed value (= mime).
    await _r2.put<void>(
      uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          Headers.contentLengthHeader: length,
          Headers.contentTypeHeader: mime,
        },
      ),
      onSendProgress: onProgress,
      cancelToken: cancel,
    );
    // 3) Confirm — creates the DB row and returns the file.
    final done = await _dio.post<Map<String, dynamic>>(
      CloudConfig.filesConfirmUpload,
      data: {
        'upload_id': uploadId,
        'storage_key': storageKey,
        'name': name,
        'size': length,
        'mime_type': mime,
        'folder_id': ?folderId,
      },
      cancelToken: cancel,
    );
    return DriveFile.fromJson(
      (done.data?['data'] as Map<String, dynamic>?) ?? const {},
    );
  });

  Future<DriveFile> _uploadMultipart({
    required File file,
    required String name,
    required String mime,
    required int length,
    required String? folderId,
    required ProgressCb? onProgress,
    required CancelToken? cancel,
  }) => _call(() async {
    // 1) Init multipart — reserves quota + presigns every part.
    final init = await _dio.post<Map<String, dynamic>>(
      CloudConfig.filesMultipartInit,
      data: {
        'name': name,
        'size': length,
        'mime_type': mime,
        'folder_id': ?folderId,
      },
      cancelToken: cancel,
    );
    final meta = init.data?['data'] as Map<String, dynamic>? ?? const {};
    final uploadId = meta['upload_id'] as String?;
    final fileId = meta['file_id'] as String?;
    final storageKey = meta['storage_key'] as String?;
    final parts = (meta['parts'] as List?) ?? const [];
    if (uploadId == null || fileId == null || storageKey == null) {
      throw const DriveException('bad multipart init', code: 'UNKNOWN');
    }
    // 2) PUT each part; capture ETags. Progress is cumulative across parts.
    final etags = <Map<String, dynamic>>[];
    var uploaded = 0;
    for (final raw in parts) {
      if (raw is! Map) continue;
      final partNumber = (raw['part_number'] as num?)?.toInt() ?? 0;
      final url = raw['upload_url'] as String?;
      if (partNumber < 1 || url == null) continue;
      final start = (partNumber - 1) * _partSize;
      final end = (start + _partSize).clamp(0, length);
      final base = uploaded;
      final res = await _r2.put<void>(
        url,
        data: file.openRead(start, end),
        options: Options(headers: {Headers.contentLengthHeader: end - start}),
        onSendProgress: (sent, _) => onProgress?.call(base + sent, length),
        cancelToken: cancel,
      );
      final etag = res.headers.value('etag') ?? '';
      etags.add({'part_number': partNumber, 'etag': etag});
      uploaded = end;
    }
    // 3) Complete — assembles the object in R2 + creates the DB row.
    final done = await _dio.post<Map<String, dynamic>>(
      CloudConfig.filesMultipartComplete,
      data: {
        'upload_id': uploadId,
        'file_id': fileId,
        'storage_key': storageKey,
        'name': name,
        'size': length,
        'mime_type': mime,
        'parts': etags,
        'folder_id': ?folderId,
      },
      cancelToken: cancel,
    );
    return DriveFile.fromJson(
      (done.data?['data'] as Map<String, dynamic>?) ?? const {},
    );
  });

  // ---- Shares ---------------------------------------------------------------

  /// Create a share-link for a file (or folder). Optional [password] and
  /// [expiresInHours]. Returns the link (with the full copyable `url`).
  Future<ShareLink> createShare({
    String? fileId,
    String? folderId,
    String? password,
    int? expiresInHours,
  }) => _call(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      CloudConfig.shares,
      data: {
        'file_id': ?fileId,
        'folder_id': ?folderId,
        if (password != null && password.isNotEmpty) 'password': password,
        if (expiresInHours != null && expiresInHours > 0)
          'expires_in_hours': expiresInHours,
      },
    );
    return ShareLink.fromJson(
      (res.data?['data'] as Map<String, dynamic>?) ?? const {},
    );
  });

  /// All of the caller's active share-links (newest first).
  Future<List<ShareLink>> shares() => _call(() async {
    final res = await _dio.get<Map<String, dynamic>>(CloudConfig.shares);
    final data = (res.data?['data'] as List?) ?? const [];
    return [
      for (final s in data)
        if (s is Map<String, dynamic>) ShareLink.fromJson(s),
    ];
  });

  /// Revoke (soft-delete) a share-link. Idempotent server-side.
  Future<void> revokeShare(String id) =>
      _call(() => _dio.delete<Map<String, dynamic>>(CloudConfig.share(id)));

  // ---- helpers --------------------------------------------------------------

  DriveFilePage _filePage(Map<String, dynamic>? body, int fallbackPage) {
    final list = (body?['data'] as List?) ?? const [];
    final pag = body?['pagination'] as Map<String, dynamic>?;
    return DriveFilePage(
      files: [
        for (final f in list)
          if (f is Map<String, dynamic>) DriveFile.fromJson(f),
      ],
      page: (pag?['page'] as num?)?.toInt() ?? fallbackPage,
      totalPages: (pag?['total_pages'] as num?)?.toInt() ?? 1,
      total: (pag?['total'] as num?)?.toInt() ?? list.length,
    );
  }

  /// Run an authenticated call, mapping [DioException]s to [DriveException].
  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  DriveException _map(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return DriveException(
        (err['message'] as String?) ?? '',
        code: err['code'] as String?,
        status: e.response?.statusCode,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return const DriveException('network error', code: 'NETWORK');
      case DioExceptionType.cancel:
        return const DriveException('cancelled', code: 'CANCELLED');
      default:
        return DriveException(
          e.message ?? 'unknown error',
          code: 'UNKNOWN',
          status: e.response?.statusCode,
        );
    }
  }
}
