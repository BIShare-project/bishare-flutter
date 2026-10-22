import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
import 'vault_background.dart';
import 'vault_file_work.dart';
import 'vault_files.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';
import 'vault_sync.dart';
import 'vault_thumbs.dart';

/// The upload queue (drive-plan.md task 4.4). For each file:
///
/// 1. read it once (on another isolate): its SHA-256, its size, and its
///    compressed copy when the type is worth it and the result is at least
///    10% smaller (VAULT-SPEC "Compression"); a file this vault already holds
///    (same SHA-256 and size in the local index) is linked to the stored
///    copy, nothing is sent;
/// 2. seal it with a fresh file key (BSE2) to a file that outlives a restart,
///    because a second sealing would give different bytes than the parts
///    already sent; written under a temporary name, so a sealing cut short is
///    never sent; the file must still be the one that was read;
/// 3. reserve quota with the dedupe tag (the server may answer with a blob of
///    the same content: link to it once its hash and size match ours);
/// 4. send in one PUT, or in parts whose ETags are kept after each one; a
///    send that makes no progress for a minute stops (slow is fine, stuck is
///    not);
/// 5. commit the object with its sealed metadata, then pull the index. A
///    commit whose answer was lost is asked again, not sent again.
///
/// A lost connection stops the queue and, in the app, it starts again by
/// itself after a pause ([retryAfter], growing up to five minutes). A file
/// that fails for good leaves nothing behind in the work folder.
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
    this.retryAfter,
    this.mayStart,
  }) : _thumbs = thumbs,
       _api = api,
       _keys = keys,
       _dao = dao,
       _sync = sync,
       // No send timeout: a large part on a slow line takes as long as it
       // takes. The watchdog in [_put] stops a send that makes no progress.
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
  final VaultSync _sync;
  final Dio _http;
  final Future<Directory> Function() _workDir;
  final VaultThumbs? _thumbs;

  /// Maximum security sends no dedupe tag and compresses nothing
  /// (VAULT-SPEC: stored sizes then say nothing about the content).
  bool maximumSecurity;

  /// The first pause before the queue tries again by itself after a lost
  /// connection; null: only when asked ([run]).
  final Duration? retryAfter;

  /// Whether [t] may go up now (photo backup on mobile data waits when the
  /// person asked for Wi-Fi only). Null: everything may.
  Future<bool> Function(VaultTransfer t)? mayStart;

  static const _partRetries = 3;

  /// A send with no progress for this long is treated as a lost connection.
  static const _stalled = Duration(seconds: 60);

  static const _retryMax = Duration(minutes: 5);

  Future<void>? _running;
  CancelToken? _cancel;
  int? _current;
  final Set<int> _cancelled = {};
  final Map<int, ({int done, int total})> _progress = {};
  Timer? _retryTimer;
  Duration? _nextRetry;

  /// Bumped by [stop]: a run from before it ends at its next step.
  int _epoch = 0;

  /// Bytes sent of the file being uploaded now, by queue id.
  ({int done, int total})? progressOf(int id) => _progress[id];

  static Future<Directory> _defaultWorkDir() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/vault/work',
    );
    await dir.create(recursive: true);
    if (!_outOfBackups) {
      // Plain copies of what goes up: never in an iCloud backup (audit P11;
      // Android's backup rules leave the folder out too). Once a run, for
      // folders made by an earlier version as well.
      _outOfBackups = true;
      await VaultBackground.excludeFromBackup(dir.path);
    }
    return dir;
  }

  static bool _outOfBackups = false;

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

  /// Queue one photo or video of the device's library (photo backup) for
  /// the folder [parent]; [name] is the library's own file name. When it is
  /// done the asset is marked backed up. Returns the queue id.
  Future<int> enqueueAsset(
    File file, {
    required String assetId,
    required String name,
    String? parent,
  }) async {
    final taken = {
      for (final t in await _dao.pendingTransfers())
        if (t.direction == 'up' && t.parent == parent) t.name.toLowerCase(),
      for (final o in await _dao.liveChildren(parent)) o.name.toLowerCase(),
    };
    final now = DateTime.now().millisecondsSinceEpoch;
    return _dao.enqueue(
      VaultTransfersCompanion.insert(
        direction: 'up',
        objectId: Rust.vaultGenerateObjectId(),
        parent: Value(parent),
        name: freeNameIn(
          taken,
          VaultMetaCodec.validName(name) ? name : 'photo',
        ),
        localPath: file.path,
        size: await file.length(),
        state: 'queued',
        createdAt: now,
        updatedAt: now,
        assetId: Value(assetId),
      ),
    );
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

  /// Put a stopped upload back in the queue (after "Upload stopped", or one
  /// waiting for the connection).
  Future<void> retry(int id) async {
    await _set(id, state: 'queued', error: null);
    unawaited(run());
  }

  /// Work through the queue until it is empty or the network goes. Calls
  /// while it runs join the same run.
  Future<void> run() {
    if (_held) return Future.value();
    _retryTimer?.cancel();
    _retryTimer = null;
    return _running ??=
        () async {
          await beforeRun?.call();
          await _runAll();
        }().whenComplete(() {
          _running = null;
        });
  }

  /// The queue being worked through, if it is (for the time iOS gives an
  /// app that leaves the screen mid-upload).
  Future<void>? get running => _running;

  /// Awaited before the queue starts: the app makes a background run that
  /// is sending stop first (VaultBackground.takeOver).
  Future<void> Function()? beforeRun;

  bool _held = false;

  /// Stop sending, keep everything for later: the upload in flight stops
  /// where it is (its parts sent so far stay sent) and nothing starts until
  /// [release]. Photo backup's background run uses it when its time is up,
  /// or when the app opens and takes over the queue.
  Future<void> hold() async {
    _held = true;
    _epoch++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancel?.cancel();
    try {
      await _running;
    } on Object {
      // Stopped is what was asked.
    }
  }

  void release() => _held = false;

  /// Sign-out: the upload in flight stops, nothing starts again by itself,
  /// and the work folder (sealed files, compressed copies) goes.
  Future<void> stop() async {
    _epoch++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _cancel?.cancel();
    try {
      final work = await _workDir();
      if (await work.exists()) await work.delete(recursive: true);
    } on Object catch (e) {
      debugPrint('[vault] work folder: $e');
    }
  }

  Future<void> _runAll() async {
    final epoch = _epoch;
    while (epoch == _epoch) {
      VaultTransfer? next;
      for (final t in await _dao.pendingTransfers()) {
        if (t.direction != 'up' || _cancelled.contains(t.id)) continue;
        final gate = mayStart;
        if (gate != null && !await gate(t)) continue;
        next = t;
        break;
      }
      if (next == null) {
        _nextRetry = null;
        return;
      }
      _current = next.id;
      _cancel = CancelToken();
      try {
        await _upload(next);
        _nextRetry = null;
      } on _Stop catch (s) {
        if (s.state == 'failed') {
          await _fail(next.id, s.code);
        } else {
          await _set(next.id, state: s.state, error: s.code);
        }
        if (s.state != 'failed' && s.state != 'cancelled') return;
      } on VaultApiException catch (e) {
        if (_retryable(e.code)) {
          await _set(next.id, error: 'NETWORK');
          _later(epoch);
          return;
        }
        await _fail(next.id, e.code);
      } on DioException catch (e) {
        if (CancelToken.isCancel(e) && _cancelled.contains(next.id)) {
          await _cleanup((await _dao.transfer(next.id)) ?? next);
          await _set(next.id, state: 'cancelled');
        } else if (CancelToken.isCancel(e)) {
          return; // stopped (sign-out)
        } else {
          await _set(next.id, error: 'NETWORK');
          _later(epoch);
          return;
        }
      } on Object catch (e) {
        debugPrint('[vault] upload ${next.id} failed: $e');
        await _fail(next.id, 'UNKNOWN');
      } finally {
        _current = null;
        _cancelled.remove(next.id);
        _progress.remove(next.id);
        notifyListeners();
      }
    }
  }

  /// A lost connection, a server hiccup, a full minute without progress:
  /// worth trying again.
  static bool _retryable(String code) =>
      code == 'NETWORK' || code == 'INTERNAL_ERROR' || code == 'RATE_LIMITED';

  /// Try the queue again by itself after a pause that grows with each try.
  void _later(int epoch) {
    final first = retryAfter;
    if (first == null || epoch != _epoch) return;
    final wait = _nextRetry ?? first;
    _nextRetry = wait * 2 > _retryMax ? _retryMax : wait * 2;
    _retryTimer?.cancel();
    _retryTimer = Timer(wait, () {
      if (epoch == _epoch) unawaited(run());
    });
  }

  /// Stop a queued or running upload and release what it reserved. A step
  /// already running (sealing, reserving) finishes first, then the upload
  /// stops there and gives back what that step took.
  Future<void> cancel(int id) async {
    final t = await _dao.transfer(id);
    if (t == null) return;
    _cancelled.add(id);
    if (_current == id) _cancel?.cancel();
    final vaultId = await _keys.vaultId();
    if (t.uploadId != null && vaultId != null) {
      try {
        await _api.abort(vaultId, t.uploadId!);
      } on Object {
        // The reservation runs out by itself.
      }
    }
    if (_current != id) {
      _cancelled.remove(id);
      await _cleanup(t);
    }
    await _set(id, state: 'cancelled');
  }

  /// Between steps: a cancel that came while the step ran stops here.
  Future<void> _check(VaultTransfer t, String vaultId) async {
    if (!_cancelled.contains(t.id)) return;
    final now = await _dao.transfer(t.id);
    final reserved = now?.uploadId;
    if (reserved != null) {
      try {
        await _api.abort(vaultId, reserved);
      } on Object {
        // The reservation runs out by itself.
      }
    }
    await _cleanup(now ?? t);
    throw const _Stop('cancelled', 'CANCELLED');
  }

  // ---- one file ----------------------------------------------------------------------

  /// [changed]: how many times the file was edited while it was being read
  /// and sealed; it is read again each time, then given up on.
  Future<void> _upload(VaultTransfer t0, {int changed = 0}) async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) throw const _Stop('queued', 'NO_KEY');
    var t = t0;
    final source = File(t.localPath);

    // Everything was sent and only the commit's answer is missing: ask again.
    if (t.uploadId != null && t.encMeta != null && _allSent(t.partsDone)) {
      return _commit(vaultId, vk, t);
    }

    // A sealed file is made once. Without it (the app stopped while sealing,
    // or the work folder went), the upload starts over with a fresh file key:
    // a key is never used for two different sealings.
    var sealed = t.sealedPath == null ? null : File(t.sealedPath!);
    if (t.encMeta != null && (sealed == null || !await sealed.exists())) {
      await _reset(vaultId, t);
      t = (await _dao.transfer(t.id))!;
      sealed = null;
    }

    // 1. One read of the file: hash, size, the compressed copy.
    if (t.encMeta == null) {
      if (!await source.exists()) throw const _Stop('failed', 'MISSING');
      await _set(t.id, state: 'sealing');
      final mime = lookupMimeType(t.name) ?? 'application/octet-stream';
      final work = await _workDir();
      final snap = await VaultFileWork.snapshot(
        source.path,
        zPath: _wantsCompression(t, mime)
            ? '${work.path}/${t.objectId}.z'
            : null,
      );
      await _check(t, vaultId);
      if (!maximumSecurity) {
        final same = await _dao.fileWithHash(VaultMetaCodec.b64u(snap.hash));
        if (same != null &&
            same.size == snap.size &&
            await _linkTo(
              vaultId,
              vk,
              t,
              same,
              hash: snap.hash,
              size: snap.size,
              mime: mime,
              mtime: snap.modifiedMs,
            )) {
          await _cleanup(t);
          return;
        }
      }
      final meta = VaultMeta(
        kind: 'file',
        name: t.name,
        parent: t.parent,
        mtimeMs: snap.modifiedMs,
        size: snap.size,
        mime: mime,
        fileKey: Rust.vaultGenerateFileKey(),
        hash: snap.hash,
        compression: snap.compressed ? 'deflate' : null,
      );
      await _dao.updateTransfer(
        t.id,
        VaultTransfersCompanion(
          encMeta: Value(VaultMetaCodec.seal(vk, vaultId, t.objectId, meta)),
          size: Value(snap.size),
          updatedAt: Value(_now()),
        ),
      );
      t = (await _dao.transfer(t.id))!;
    }
    final meta = VaultMetaCodec.open(vk, vaultId, t.objectId, t.encMeta!);

    // 2. The sealed file, made once.
    try {
      sealed ??= await _seal(t, meta);
    } on _Changed {
      if (changed >= 2) throw const _Stop('failed', 'CHANGED');
      await _reset(vaultId, t);
      return _upload((await _dao.transfer(t.id))!, changed: changed + 1);
    }
    t = (await _dao.transfer(t.id))!;
    await _check(t, vaultId);
    final sealedSize = await sealed.length();

    // 3. Reserve, or link to the same content.
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
              hash: meta.hash!,
              size: meta.size!,
              mime: meta.mime!,
              mtime: meta.mtimeMs,
            )) {
          await _cleanup(t);
          return;
        }
        // No object of ours holds that blob, or its content is not ours:
        // send the bytes after all.
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
      await _check(t, vaultId);
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
        await _reset(vaultId, t);
        return _upload((await _dao.transfer(t.id))!);
      }
      t = (await _dao.transfer(t.id))!;
    }
    await _check(t, vaultId);
    return _commit(vaultId, vk, t);
  }

  /// 5. Commit, then the index and the thumbnail. A repeat of a commit that
  /// went through is answered from the object; a reservation that ran out
  /// before any commit starts the upload over.
  Future<void> _commit(String vaultId, Uint8List vk, VaultTransfer t) async {
    await _set(t.id, state: 'finishing');
    final meta = VaultMetaCodec.open(vk, vaultId, t.objectId, t.encMeta!);
    final plan = jsonDecode(t.partsDone ?? '{}') as Map<String, dynamic>;
    final multipart = (plan['size'] as num? ?? 0) > 0;
    try {
      await _api.complete(
        vaultId,
        t.uploadId!,
        objectId: t.objectId,
        encMeta: t.encMeta!,
        parts: multipart ? _doneParts(plan) : null,
      );
    } on VaultApiException catch (e) {
      if (e.code == 'VAULT_OBJECT_EXISTS') {
        // This object is ours: an earlier try went through.
      } else if (e.code == 'VAULT_UPLOAD_NOT_FOUND' ||
          e.code == 'VAULT_UPLOAD_INCOMPLETE') {
        await _reset(vaultId, t);
        return _upload((await _dao.transfer(t.id))!);
      } else {
        rethrow;
      }
    }
    await _cleanup(t);
    await _set(t.id, state: 'done', error: null);
    await _markAsset(t, meta.hash);
    await _thumb(t, vaultId, meta);
    unawaited(_sync.pull().catchError((Object _) {}));
  }

  /// Photo backup: the library asset behind [t] is in the Drive now.
  Future<void> _markAsset(VaultTransfer t, Uint8List? hash) async {
    final asset = t.assetId;
    if (asset == null || hash == null) return;
    await _dao.markAssetBackedUp(asset, VaultMetaCodec.b64u(hash), t.objectId);
  }

  static bool _allSent(String? partsDone) {
    if (partsDone == null) return false;
    final plan = jsonDecode(partsDone) as Map<String, dynamic>;
    final parts = (plan['parts'] as num? ?? 0).toInt();
    return parts > 0 && _doneParts(plan).length == parts;
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
  /// (and compression) come from the object that holds it, once that
  /// object's hash and size are those of the file being added (VAULT-SPEC
  /// "Dedupe": the server's word that two blobs match is never enough).
  /// False when they differ, the holder's metadata does not open, or the
  /// server no longer has the blob; the caller then sends the bytes.
  Future<bool> _linkTo(
    String vaultId,
    Uint8List vk,
    VaultTransfer t,
    VaultObject holder, {
    required Uint8List hash,
    required int size,
    required String mime,
    required int mtime,
  }) async {
    final VaultMeta theirs;
    try {
      theirs = VaultMetaCodec.open(vk, vaultId, holder.id, holder.encMeta);
    } on Object {
      return false;
    }
    final theirHash = theirs.hash;
    if (theirs.size != size ||
        theirHash == null ||
        !listEquals(theirHash, hash)) {
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
    final code = res['code'] as String?;
    if (res['ok'] != true && code == 'VAULT_BLOB_NOT_FOUND') return false;
    // VAULT_OBJECT_EXISTS: this object is ours, an earlier try went through.
    if (res['ok'] != true && code != 'VAULT_OBJECT_EXISTS') {
      throw VaultApiException(
        code ?? 'UNKNOWN',
        res['message'] as String? ?? '',
      );
    }
    await _set(t.id, state: 'done', error: null);
    await _markAsset(t, hash);
    await _thumb(t, vaultId, meta);
    unawaited(_sync.pull().catchError((Object _) {}));
    return true;
  }

  bool _wantsCompression(VaultTransfer t, String mime) =>
      !maximumSecurity &&
      t.size <= VaultMetaCodec.compressMax &&
      VaultMetaCodec.compressible(mime, t.name);

  Future<File> _seal(VaultTransfer t, VaultMeta meta) async {
    await _set(t.id, state: 'sealing');
    final work = await _workDir();
    final compressed = meta.compression == 'deflate';
    final input = compressed
        ? File('${work.path}/${t.objectId}.z')
        : File(t.localPath);
    if (!await input.exists()) {
      throw _Stop('failed', compressed ? 'COMPRESSION' : 'MISSING');
    }
    final plainSize = await input.length();
    final out = File('${work.path}/${t.objectId}.bse2');
    final tmp = File('${out.path}.tmp');
    await Bse2.encryptFile(input: input, output: tmp, key: meta.fileKey!);
    // The file read in step 1 is the one sealed: not edited meanwhile, and
    // the container is whole.
    final same =
        compressed ||
        (plainSize == meta.size &&
            (await input.lastModified()).millisecondsSinceEpoch ==
                meta.mtimeMs);
    if (!same || await tmp.length() != Bse2.ciphertextSize(plainSize)) {
      await tmp.delete();
      throw const _Changed();
    }
    await tmp.rename(out.path);
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
    await _put(url, () => sealed.openRead(), len, (s) => _report(t.id, s, len));
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

  /// One PUT to R2 with a watchdog: no progress for [_stalled] ends it as a
  /// lost connection. The ETag, when the server sent one.
  Future<String?> _put(
    String url,
    Stream<List<int>> Function() data,
    int length,
    void Function(int sent) onSent,
  ) async {
    final outer = _cancel;
    final token = CancelToken();
    unawaited(outer?.whenCancel.then((_) => token.cancel()));
    Timer? idle;
    var stalled = false;
    void arm() {
      idle?.cancel();
      idle = Timer(_stalled, () {
        stalled = true;
        token.cancel('stalled');
      });
    }

    arm();
    try {
      final res = await _http.put<void>(
        url,
        data: data(),
        options: Options(headers: {Headers.contentLengthHeader: length}),
        onSendProgress: (sent, _) {
          arm();
          onSent(sent);
        },
        cancelToken: token,
      );
      return res.headers.value('etag');
    } on DioException catch (e) {
      if (stalled && CancelToken.isCancel(e)) {
        throw const VaultApiException('NETWORK', 'no progress');
      }
      rethrow;
    } finally {
      idle?.cancel();
    }
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
          etag = await _put(
            await urlFor(n),
            () => sealed.openRead(start, end),
            end - start,
            (s) => _report(t.id, sent + s, len),
          );
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

  /// Back to the start: the reservation released, the sealed file and the
  /// compressed copy gone, the metadata (with its file key) dropped.
  Future<void> _reset(String vaultId, VaultTransfer t) async {
    if (t.uploadId != null) {
      try {
        await _api.abort(vaultId, t.uploadId!);
      } on Object {
        // Expired already.
      }
    }
    await _cleanup(t);
    await _dao.updateTransfer(
      t.id,
      VaultTransfersCompanion(
        encMeta: const Value(null),
        sealedPath: const Value(null),
        uploadId: const Value(null),
        partsDone: const Value(null),
        bytesDone: const Value(0),
        updatedAt: Value(_now()),
      ),
    );
  }

  /// Failed for good (until "Try again"): nothing is kept around for it, not
  /// the reservation, not the sealed file, not the compressed copy, which is
  /// the content without encryption.
  Future<void> _fail(int id, String code) async {
    final t = await _dao.transfer(id);
    debugPrint('[vault] upload $id (${t?.assetId ?? 'file'}) stopped: $code');
    final vaultId = await _keys.vaultId();
    if (t != null && vaultId != null) await _reset(vaultId, t);
    await _set(id, state: 'failed', error: code);
  }

  Future<void> _cleanup(VaultTransfer t) async {
    final work = await _workDir();
    for (final f in [
      if (t.sealedPath != null) File(t.sealedPath!),
      File('${work.path}/${t.objectId}.z'),
      File('${work.path}/${t.objectId}.z.tmp'),
      File('${work.path}/${t.objectId}.bse2'),
      File('${work.path}/${t.objectId}.bse2.tmp'),
    ]) {
      try {
        if (await f.exists()) await f.delete();
      } on Object {
        // Gone already.
      }
    }
  }

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

/// The file changed between the read that hashed it and the sealing.
class _Changed implements Exception {
  const _Changed();
}
