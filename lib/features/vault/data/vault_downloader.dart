import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/crypto/bse2.dart';
import '../../../core/io/preserve_mtime.dart';
import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_api.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';
import 'vault_sync.dart';

/// Getting a Drive file back (drive-plan.md task 4.5): a presigned GET straight
/// from R2, BSE2-open with the file key from the object's sealed metadata,
/// inflate when it was stored compressed, then the original modification
/// time on the result.
///
/// Opening needs the whole sealed file on disk first (BSE2 authenticates every
/// record and the whole length), so a download takes its ciphertext size of
/// free space in the cache folder while it runs.
class VaultDownloader {
  VaultDownloader({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    VaultSync? sync,
    Dio? http,
    Future<Directory> Function()? workDir,
  }) : _api = api,
       _keys = keys,
       _dao = dao,
       _sync = sync,
       _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _workDir = workDir ?? _defaultWorkDir;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final VaultSync? _sync;
  final Dio _http;
  final Future<Directory> Function() _workDir;

  static Future<Directory> _defaultWorkDir() async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/vault-get');
    await dir.create(recursive: true);
    return dir;
  }

  /// Write object [objectId]'s content to [target] (which must not exist or
  /// may be overwritten). [onProgress] reports stored bytes received.
  Future<File> download(
    String objectId,
    File target, {
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) {
      throw const VaultApiException('VAULT_NO_KEY', 'No key on this device');
    }
    var obj = await _dao.object(objectId);
    if (obj == null && _sync != null) {
      // Made on another device a moment ago: the index catches up first.
      await _sync.pull();
      obj = await _dao.object(objectId);
    }
    if (obj == null || obj.kind != 'file') {
      throw const VaultApiException('VAULT_OBJECT_NOT_FOUND', 'Not a file');
    }
    final meta = VaultMetaCodec.open(vk, vaultId, objectId, obj.encMeta);

    final url = await _urlFor(vaultId, objectId);
    final work = await _workDir();
    final sealed = File('${work.path}/$objectId.bse2');
    final plain = File('${work.path}/$objectId.plain');
    try {
      await _http.download(
        url,
        sealed.path,
        onReceiveProgress: onProgress,
        cancelToken: cancel,
        deleteOnError: true,
      );
      await Bse2.decryptFile(input: sealed, output: plain, key: meta.fileKey!);
      await sealed.delete();
      if (meta.compression == 'deflate') {
        final bytes = Rust.vaultInflateRaw(
          await plain.readAsBytes(),
          meta.size!,
        );
        await plain.writeAsBytes(bytes, flush: true);
      }
      await target.parent.create(recursive: true);
      final File done;
      try {
        done = await plain.rename(target.path);
      } on FileSystemException {
        // Another volume: copy, then drop the cache copy.
        await plain.copy(target.path);
        await plain.delete();
        return await _finish(File(target.path), meta);
      }
      return await _finish(done, meta);
    } finally {
      for (final f in [sealed, plain]) {
        try {
          if (await f.exists()) await f.delete();
        } on Object {
          // Cache; the system clears it.
        }
      }
    }
  }

  Future<File> _finish(File f, VaultMeta meta) async {
    await applyReceivedMtime(f, meta.mtimeMs);
    return f;
  }

  /// A download URL, waiting when the server hands them out slowly (past the
  /// read-back allowance, drive-plan.md "Reading old data back").
  Future<String> _urlFor(String vaultId, String objectId) async {
    for (var round = 0; round < 20; round++) {
      final item = (await _api.downloads(vaultId, [objectId])).single;
      if (item.missing) {
        throw const VaultApiException(
          'VAULT_OBJECT_NOT_FOUND',
          'The file is gone',
        );
      }
      if (item.url != null) return item.url!;
      final wait = item.retryAfterMs ?? 1000;
      debugPrint('[vault] download of $objectId paced: ${wait}ms');
      await Future<void>.delayed(Duration(milliseconds: wait));
    }
    throw const VaultApiException('RATE_LIMITED', 'Try again later');
  }
}
