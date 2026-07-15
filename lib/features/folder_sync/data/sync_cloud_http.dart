import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/constants/cloud.dart';
import '../../drive/data/drive_service.dart';
import 'cloud_store.dart';

/// Production [SyncCloudStore]: the drive backend over the SAME authenticated
/// client + upload machinery the Drive UI uses (presigned/multipart, quota,
/// retries) — zero new endpoints (Q4). Blobs cross as opaque ciphertext files
/// named by their ciphertext hash inside a hidden `.bishare-sync-<pairId>`
/// folder (filtered out of the Drive UI, Q3).
class HttpSyncCloudStore implements SyncCloudStore {
  HttpSyncCloudStore(
    this._drive,
    this._authedDio, {
    Directory? scratchDir,
  }) : _scratch = scratchDir ?? Directory.systemTemp;

  final DriveService _drive;

  /// Bearer + silent-refresh dio (check-exists + sync-status have no
  /// DriveService wrapper — they're sync-only calls).
  final Dio _authedDio;

  final Directory _scratch;

  /// Plain client for presigned R2 GETs (no Bearer — the URL is the auth).
  final Dio _plain = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
      responseType: ResponseType.bytes,
    ),
  );

  @override
  Future<String> ensureFolder(String name) async {
    final existing = await _drive.folders(includeHidden: true);
    for (final f in existing) {
      if (f.name == name) return f.id;
    }
    return (await _drive.createFolder(name)).id;
  }

  @override
  Future<Map<String, bool>> checkExists(List<String> hashes) async {
    if (hashes.isEmpty) return const {};
    final res = await _authedDio.post<Map<String, dynamic>>(
      CloudConfig.filesCheckExists,
      data: {'hashes': hashes},
    );
    final data = (res.data?['data'] as Map<String, dynamic>?) ?? const {};
    final map = (data['exists'] as Map<String, dynamic>?) ?? data;
    return {for (final h in hashes) h: map[h] == true};
  }

  @override
  Future<CloudFileRef> upload(
    String folderId,
    String name,
    Uint8List bytes,
  ) async {
    // DriveService.upload speaks files (streams, hashes, multipart) — stage
    // the ciphertext to a scratch file rather than duplicating that machinery.
    final tmp = File(
      '${_scratch.path}${Platform.pathSeparator}'
      '.bishare-sync-up-$name.tmp',
    );
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      final f = await _drive.upload(tmp, folderId: folderId, name: name);
      return CloudFileRef(id: f.id, name: f.name, size: f.size);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }

  @override
  Future<List<CloudFileRef>> list(String folderId) async {
    final out = <CloudFileRef>[];
    var page = 1;
    while (true) {
      final res = await _drive.files(
        folderId: folderId,
        page: page,
        perPage: 100,
      );
      out.addAll([
        for (final f in res.files)
          CloudFileRef(id: f.id, name: f.name, size: f.size),
      ]);
      if (!res.hasMore) break;
      page++;
    }
    return out;
  }

  @override
  Future<Uint8List> download(String fileId) async {
    final url = await _drive.downloadUrl(fileId);
    final res = await _plain.get<List<int>>(url);
    return Uint8List.fromList(res.data ?? const []);
  }

  @override
  Future<void> delete(String fileId) => _drive.deleteFile(fileId);

  @override
  Future<CloudSyncBeacon> beacon() async {
    final res = await _authedDio.get<Map<String, dynamic>>(
      CloudConfig.filesSyncStatus,
    );
    final d = (res.data?['data'] as Map<String, dynamic>?) ?? const {};
    return CloudSyncBeacon(
      fingerprint:
          '${d['last_sync_at']}|${d['total_files']}|${d['total_size']}',
      tier: (d['tier'] as String?) ?? 'free',
    );
  }
}
