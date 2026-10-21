import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/crypto/bse2.dart';
import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_api.dart';
import 'vault_files.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';
import 'vault_sync.dart';
import 'vault_thumbs.dart';

/// The upload queue (drive-plan.md task 4.4). For each file:
///
/// 1. hash the plaintext; a file this vault already holds (same SHA-256 in
///    the local index) is linked to the stored copy, nothing is sent;
/// 2. compress when the type is worth it and the result is at least 10%
///    smaller (VAULT-SPEC "Compression");
/// 3. seal with a fresh file key (BSE2) to a file that outlives a restart,
///    because a second sealing would give different bytes than the parts
///    already sent;
/// 4. reserve quota with the dedupe tag (the server may answer with a blob
///    of the same content: link to it);
/// 5. send in one PUT, or in parts whose ETags are kept after each one;
/// 6. commit the object with its sealed metadata, then pull the index.
///
/// One file at a time, one part at a time: a phone on mobile data should not
/// open ten connections. The queue lives in [VaultTransfers]; [run] picks up
/// whatever a previous run left.
class VaultUploader extends ChangeNotifier {
  VaultUploader({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    required VaultSync sync,
    Dio? http,
    Future<Directory> Function()? workDir,
    VaultThumbs? thumbs,
    this.maximumSecurity = false,
  }) : _thumbs = thumbs,
       _api = api,
       _keys = keys,
       _dao = dao,
       _sync = sync,
       _http =
           http ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               sendTimeout: const Duration(minutes: 5),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _workDir = workDir ?? _defaultWorkDir;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final VaultSync _sync;
  final Dio _http;
  final Future<Directory> Function() _workDir;
  final VaultThumbs? _thumbs;

  /// Maximum security sends no dedupe tag and compresses nothing
  /// (VAULT-SPEC: stored sizes then say nothing about the content).
  bool maximumSecurity;

  static const _partRetries = 3;

  Future<void>? _running;
  CancelToken? _cancel;
  int? _current;
  final Map<int, ({int done, int total})> _progress = {};

  /// Bytes sent of the file being uploaded now, by queue id.
  ({int done, int total})? progressOf(int id) => _progress[id];

  static Future<Directory> _defaultWorkDir() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/vault/work',
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Queue [files] for the folder [parent] (null: the top of the Drive) and
  /// start the queue. A name already used there (or by a file still in the
  /// queue for the same folder) gets " (1)", " (2)", …. Returns the queue ids.
  Future<List<int>> enqueue(
    List<File> files, {
    String? parent,
    bool start = true,
  }) async {
    final ids = <int>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    final taken = {
      for (final t in await _dao.pendingTransfers())
        if (t.direction == 'up' && t.parent == parent) t.name.toLowerCase(),
      for (final o in await _dao.liveChildren(parent)) o.name.toLowerCase(),
    };
    for (final f in files) {
      final base = f.uri.pathSegments.isEmpty
          ? 'file'
          : f.uri.pathSegments.last;
      final name = freeNameIn(
        taken,
        VaultMetaCodec.validName(base) ? base : 'file',
      );
      taken.add(name.toLowerCase());
      ids.add(
        await _dao.enqueue(
          VaultTransfersCompanion.insert(
            direction: 'up',
            objectId: Rust.vaultGenerateObjectId(),
            parent: Value(parent),
            name: name,
            localPath: f.path,
            size: await f.length(),
            state: 'queued',
            createdAt: now,
            updatedAt: now,
          ),
        ),
      );
    }
    if (start) unawaited(run());
    return ids;
  }

  /// Queue a whole folder from this device: its folders are made in the Drive
  /// first (with [files]), then every file inside is queued into the matching
  /// folder. Hidden files and folders (a leading dot) are left out. Returns
  /// the number of files queued.
  Future<int> enqueueFolder(
    Directory dir,
    VaultFiles files, {
    String? parent,
  }) async {
    var count = 0;
    Future<void> walk(Directory d, String? into) async {
      final name = d.uri.pathSegments.where((p) => p.isNotEmpty).last;
      final id = await files.mkdir(name, parent: into);
      final here = <File>[];
      final subdirs = <Directory>[];
      await for (final e in d.list(followLinks: false)) {
        final base = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
        if (base.startsWith('.')) continue;
        if (e is File) here.add(e);
        if (e is Directory) subdirs.add(e);
      }
      if (here.isNotEmpty) {
        await enqueue(here, parent: id, start: false);
        count += here.length;
      }
      for (final s in subdirs) {
        await walk(s, id);
      }
    }

    await walk(dir, parent);
    unawaited(run());
    return count;
  }

  /// Put a stopped upload back in the queue (after "Upload stopped").
  Future<void> retry(int id) async {
    await _set(id, state: 'queued', error: null);
    unawaited(run());
  }

  /// Work through the queue until it is empty or the network goes. Calls
  /// while it runs join the same run.
  Future<void> run() => _running ??= _runAll().whenComplete(() {
    _running = null;
  });

  Future<void> _runAll() async {
    while (true) {
      final next = (await _dao.pendingTransfers())
          .where((t) => t.direction == 'up')
          .firstOrNull;
      if (next == null) return;
      _current = next.id;
      _cancel = CancelToken();
      try {
        await _upload(next);
      } on _Stop catch (s) {
        await _set(next.id, state: s.state, error: s.code);
        if (s.state != 'failed' && s.state != 'cancelled') return;
      } on VaultApiException catch (e) {
        if (e.code == 'NETWORK') {
          await _set(next.id, error: 'NETWORK');
          return; // try again on the next run
        }
        await _set(next.id, state: 'failed', error: e.code);
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          await _set(next.id, state: 'cancelled');
        } else {
          await _set(next.id, error: 'NETWORK');
          return;
        }
      } on Object catch (e) {
        debugPrint('[vault] upload ${next.id} failed: $e');
        await _set(next.id, state: 'failed', error: 'UNKNOWN');
      } finally {
        _current = null;
        _progress.remove(next.id);
        notifyListeners();
      }
    }
  }

  /// Stop a queued or running upload and release what it reserved.
  Future<void> cancel(int id) async {
    final t = await _dao.transfer(id);
    if (t == null) return;
    if (_current == id) _cancel?.cancel();
    final vaultId = await _keys.vaultId();
    if (t.uploadId != null && vaultId != null) {
      try {
        await _api.abort(vaultId, t.uploadId!);
      } on Object {
        // The reservation runs out by itself.
      }
    }
    await _cleanup(t);
    await _set(id, state: 'cancelled');
  }

  // ---- one file ----------------------------------------------------------------------

  Future<void> _upload(VaultTransfer t0) async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) throw const _Stop('queued', 'NO_KEY');
    var t = t0;
    final source = File(t.localPath);

    // 1-2. Metadata (with the file key) once; a resumed upload keeps it.
    if (t.encMeta == null) {
      if (!await source.exists()) throw const _Stop('failed', 'MISSING');
      await _set(t.id, state: 'sealing');
      final hash = await _sha256(source);
      final hashB64 = VaultMetaCodec.b64u(hash);
      final mime = lookupMimeType(t.name) ?? 'application/octet-stream';
      final mtime = (await source.lastModified()).millisecondsSinceEpoch;

      if (!maximumSecurity) {
        final same = await _dao.fileWithHash(hashB64);
        if (same != null &&
            await _linkTo(vaultId, vk, t, same, mime: mime, mtime: mtime)) {
          return;
        }
      }
      final meta = VaultMeta(
        kind: 'file',
        name: t.name,
        parent: t.parent,
        mtimeMs: mtime,
        size: t.size,
        mime: mime,
        fileKey: Rust.vaultGenerateFileKey(),
        hash: hash,
        compression: await _compressed(t) ? 'deflate' : null,
      );
      await _dao.updateTransfer(
        t.id,
        VaultTransfersCompanion(
          encMeta: Value(VaultMetaCodec.seal(vk, vaultId, t.objectId, meta)),
          updatedAt: Value(_now()),
        ),
      );
      t = (await _dao.transfer(t.id))!;
    }
    final meta = VaultMetaCodec.open(vk, vaultId, t.objectId, t.encMeta!);

    // 3. The sealed file, made once.
    var sealed = t.sealedPath == null ? null : File(t.sealedPath!);
    if (sealed == null || !await sealed.exists()) {
      if (t.uploadId != null) {
        // Parts of an earlier sealing may be on the server; they cannot be
        // matched by a new one. Start the upload over.
        await _forgetUpload(vaultId, t);
        t = (await _dao.transfer(t.id))!;
      }
      sealed = await _seal(t, meta);
      t = (await _dao.transfer(t.id))!;
    }
    final sealedSize = await sealed.length();

    // 4. Reserve, or link to the same content.
    if (t.uploadId == null) {
      final tag = maximumSecurity
          ? null
          : Rust.vaultDedupeTag(
              dedupeKey: Rust.vaultDedupeKey(vk),
              plaintextHash: meta.hash!,
            );
      var r = await _api.reserve(vaultId, size: sealedSize, tag: tag);
      if (r.existingBlobId != null) {
        var holder = await _dao.fileWithBlob(r.existingBlobId!);
        if (holder == null) {
          await _sync.pull();
          holder = await _dao.fileWithBlob(r.existingBlobId!);
        }
        if (holder != null &&
            await _linkTo(
              vaultId,
              vk,
              t,
              holder,
              mime: meta.mime!,
              mtime: meta.mtimeMs,
            )) {
          await _cleanup(t);
          return;
        }
        // The index has no object for that blob: send the bytes after all.
        r = await _api.reserve(vaultId, size: sealedSize);
      }
      await _dao.updateTransfer(
        t.id,
        VaultTransfersCompanion(
          uploadId: Value(r.uploadId),
          state: const Value('sending'),
          partsDone: Value(
            jsonEncode({
              'size': r.multipart ? r.partSize : 0,
              'parts': r.multipart ? r.parts : 1,
              'done': <Object>[],
            }),
          ),
          updatedAt: Value(_now()),
        ),
      );
      t = (await _dao.transfer(t.id))!;
      if (!r.multipart && r.url != null) {
        await _putSingle(t, sealed, r.url!);
      } else {
        await _putParts(vaultId, t, sealed, initial: r.partUrls);
      }
      // The parts sent (and their ETags) are in the row now.
      t = (await _dao.transfer(t.id))!;
    } else {
      await _set(t.id, state: 'sending');
      final plan = jsonDecode(t.partsDone ?? '{}') as Map<String, dynamic>;
      try {
        if ((plan['size'] as num? ?? 0) == 0) {
          await _putSingle(t, sealed, await _api.putUrl(vaultId, t.uploadId!));
        } else {
          await _putParts(vaultId, t, sealed);
        }
      } on VaultApiException catch (e) {
        if (e.code != 'VAULT_UPLOAD_NOT_FOUND') rethrow;
        // The reservation ran out while the app was closed: start over.
        await _forgetUpload(vaultId, t);
        return _upload((await _dao.transfer(t.id))!);
      }
      t = (await _dao.transfer(t.id))!;
    }

    // 6. Commit.
    await _set(t.id, state: 'finishing');
    final plan = jsonDecode(t.partsDone ?? '{}') as Map<String, dynamic>;
    final multipart = (plan['size'] as num? ?? 0) > 0;
    await _api.complete(
      vaultId,
      t.uploadId!,
      objectId: t.objectId,
      encMeta: t.encMeta!,
      parts: multipart ? _doneParts(plan) : null,
    );
    await _cleanup(t);
    await _set(t.id, state: 'done', error: null);
    await _thumb(t, vaultId, meta);
    unawaited(_sync.pull().catchError((Object _) {}));
  }

  /// The thumbnail of a photo or video just committed. Best effort: a file
  /// without one still shows its type icon.
  Future<void> _thumb(VaultTransfer t, String vaultId, VaultMeta meta) async {
    final thumbs = _thumbs;
    if (thumbs == null || !VaultThumbs.wants(meta.mime)) return;
    final source = File(t.localPath);
    if (!await source.exists()) return;
    try {
      final jpeg = await VaultThumbs.make(source, meta.mime!);
      if (jpeg == null) return;
      await thumbs.upload(vaultId, t.objectId, meta.fileKey!, jpeg);
    } on Object catch (e) {
      debugPrint('[vault] thumbnail for ${t.name}: $e');
    }
  }

  /// Point a new object at content this vault already stores: its file key
  /// (and compression) come from the object that holds it. False when that
  /// object's metadata does not open.
  Future<bool> _linkTo(
    String vaultId,
    Uint8List vk,
    VaultTransfer t,
    VaultObject holder, {
    required String mime,
    required int mtime,
  }) async {
    final VaultMeta theirs;
    try {
      theirs = VaultMetaCodec.open(vk, vaultId, holder.id, holder.encMeta);
    } on Object {
      return false;
    }
    final meta = VaultMeta(
      kind: 'file',
      name: t.name,
      parent: t.parent,
      mtimeMs: mtime,
      size: theirs.size,
      mime: mime,
      fileKey: theirs.fileKey,
      hash: theirs.hash,
      compression: theirs.compression,
    );
    final enc = VaultMetaCodec.seal(vk, vaultId, t.objectId, meta);
    final r = await _api.ops(vaultId, [
      {
        'opId': 'link-${t.objectId}',
        'type': 'link',
        'objectId': t.objectId,
        'encMeta': enc,
        'blobId': holder.blobId,
      },
    ]);
    final res = r.results.single;
    if (res['ok'] != true) {
      throw VaultApiException(
        res['code'] as String? ?? 'UNKNOWN',
        res['message'] as String? ?? '',
      );
    }
    await _set(t.id, state: 'done', error: null);
    await _thumb(t, vaultId, meta);
    unawaited(_sync.pull().catchError((Object _) {}));
    return true;
  }

  Future<bool> _compressed(VaultTransfer t) async =>
      !maximumSecurity &&
      t.size <= VaultMetaCodec.compressMax &&
      VaultMetaCodec.compressible(
        lookupMimeType(t.name) ?? 'application/octet-stream',
        t.name,
      ) &&
      (await _compressedFile(t)) != null;

  /// The raw-DEFLATE copy of [t]'s file in the work folder, kept only when
  /// it is at least 10% smaller.
  Future<File?> _compressedFile(VaultTransfer t) async {
    final out = File('${(await _workDir()).path}/${t.objectId}.z');
    if (await out.exists()) return out;
    final plain = await File(t.localPath).readAsBytes();
    final packed = Rust.vaultDeflateRaw(plain);
    if (packed.length > plain.length * 0.9) return null;
    await out.writeAsBytes(packed, flush: true);
    return out;
  }

  Future<File> _seal(VaultTransfer t, VaultMeta meta) async {
    await _set(t.id, state: 'sealing');
    final work = await _workDir();
    final input = meta.compression == 'deflate'
        ? (await _compressedFile(t) ??
              (throw const _Stop('failed', 'COMPRESSION')))
        : File(t.localPath);
    if (!await input.exists()) throw const _Stop('failed', 'MISSING');
    final out = File('${work.path}/${t.objectId}.bse2');
    await Bse2.encryptFile(input: input, output: out, key: meta.fileKey!);
    await _dao.updateTransfer(
      t.id,
      VaultTransfersCompanion(
        sealedPath: Value(out.path),
        updatedAt: Value(_now()),
      ),
    );
    return out;
  }

  Future<void> _putSingle(VaultTransfer t, File sealed, String url) async {
    final len = await sealed.length();
    await _http.put<void>(
      url,
      data: sealed.openRead(),
      options: Options(headers: {Headers.contentLengthHeader: len}),
      onSendProgress: (sent, _) => _report(t.id, sent, len),
      cancelToken: _cancel,
    );
    final plan = {
      'size': 0,
      'parts': 1,
      'done': [
        {'n': 1, 'e': ''},
      ],
    };
    await _dao.updateTransfer(
      t.id,
      VaultTransfersCompanion(
        partsDone: Value(jsonEncode(plan)),
        bytesDone: Value(len),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<void> _putParts(
    String vaultId,
    VaultTransfer t,
    File sealed, {
    Map<int, String> initial = const {},
  }) async {
    final len = await sealed.length();
    final plan = jsonDecode(t.partsDone!) as Map<String, dynamic>;
    final partSize = (plan['size'] as num).toInt();
    final parts = (plan['parts'] as num).toInt();
    final done = {for (final p in _doneParts(plan)) p.partNumber: p.etag};
    final urls = Map<int, String>.of(initial);

    Future<String> urlFor(int n) async {
      final cached = urls[n];
      if (cached != null) return cached;
      final want = [
        for (var i = n; i <= parts && i < n + 100; i++)
          if (!done.containsKey(i)) i,
      ];
      urls.addAll(await _api.partUrls(vaultId, t.uploadId!, want));
      return urls[n] ??
          (throw const VaultApiException('UNKNOWN', 'no part URL'));
    }

    var sent = done.keys.fold<int>(
      0,
      (sum, n) => sum + min(partSize, len - (n - 1) * partSize),
    );
    for (var n = 1; n <= parts; n++) {
      if (done.containsKey(n)) continue;
      final start = (n - 1) * partSize;
      final end = min(start + partSize, len);
      String? etag;
      for (var attempt = 0; ; attempt++) {
        try {
          final res = await _http.put<void>(
            await urlFor(n),
            data: sealed.openRead(start, end),
            options: Options(
              headers: {Headers.contentLengthHeader: end - start},
            ),
            onSendProgress: (s, _) => _report(t.id, sent + s, len),
            cancelToken: _cancel,
          );
          etag = res.headers.value('etag');
          break;
        } on DioException catch (e) {
          if (CancelToken.isCancel(e) || attempt >= _partRetries) rethrow;
          urls.remove(n); // a fresh URL in case this one expired
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
      if (etag == null || etag.isEmpty) {
        throw const VaultApiException(
          'UNKNOWN',
          'a part came back without an ETag',
        );
      }
      done[n] = etag;
      sent += end - start;
      plan['done'] = [
        for (final e in done.entries) {'n': e.key, 'e': e.value},
      ];
      await _dao.updateTransfer(
        t.id,
        VaultTransfersCompanion(
          partsDone: Value(jsonEncode(plan)),
          bytesDone: Value(sent),
          updatedAt: Value(_now()),
        ),
      );
    }
  }

  static List<({int partNumber, String etag})> _doneParts(
    Map<String, dynamic> plan,
  ) {
    final list = [
      for (final p in (plan['done'] as List?) ?? const [])
        (partNumber: ((p as Map)['n'] as num).toInt(), etag: p['e'] as String),
    ]..sort((a, b) => a.partNumber.compareTo(b.partNumber));
    return list;
  }

  Future<void> _forgetUpload(String vaultId, VaultTransfer t) async {
    if (t.uploadId != null) {
      try {
        await _api.abort(vaultId, t.uploadId!);
      } on Object {
        // Expired already.
      }
    }
    await _dao.updateTransfer(
      t.id,
      VaultTransfersCompanion(
        uploadId: const Value(null),
        partsDone: const Value(null),
        bytesDone: const Value(0),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<void> _cleanup(VaultTransfer t) async {
    final work = await _workDir();
    for (final f in [
      if (t.sealedPath != null) File(t.sealedPath!),
      File('${work.path}/${t.objectId}.z'),
      File('${work.path}/${t.objectId}.bse2'),
    ]) {
      try {
        if (await f.exists()) await f.delete();
      } on Object {
        // Gone already.
      }
    }
  }

  static Future<Uint8List> _sha256(File f) async =>
      Uint8List.fromList((await sha256.bind(f.openRead()).first).bytes);

  void _report(int id, int done, int total) {
    _progress[id] = (done: done, total: total);
    notifyListeners();
  }

  Future<void> _set(int id, {String? state, Object? error = _keep}) =>
      _dao.updateTransfer(
        id,
        VaultTransfersCompanion(
          state: state == null ? const Value.absent() : Value(state),
          error: identical(error, _keep)
              ? const Value.absent()
              : Value(error as String?),
          updatedAt: Value(_now()),
        ),
      );

  static const _keep = Object();

  static int _now() => DateTime.now().millisecondsSinceEpoch;
}

/// Ends one upload with a state and a reason.
class _Stop implements Exception {
  const _Stop(this.state, this.code);
  final String state;
  final String code;
}
