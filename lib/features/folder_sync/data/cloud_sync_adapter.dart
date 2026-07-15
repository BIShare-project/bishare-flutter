import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/storage/app_database.dart';
import '../../../core/storage/sync_tables.dart';
import '../../../core/sync/manifest_store.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/sync/sync_paths.dart';
import 'cloud_store.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'sync_wire.dart';

/// Why a cloud push/pull was skipped (surfaced as a badge, never an error).
enum CloudSyncGate { ok, notLanCloud, notPro, noPairKey }

/// Result of one cloud push/pull.
class CloudSyncReport {
  const CloudSyncReport({
    required this.gate,
    this.uploaded = 0,
    this.downloaded = 0,
    this.applied = 0,
    this.skipped = false,
  });

  final CloudSyncGate gate;
  final int uploaded;
  final int downloaded;
  final int applied;

  /// Pull only: the beacon was unchanged — nothing was fetched.
  final bool skipped;
}

/// Store-and-forward over the drive backend (§5.2, Q4 manifest-as-file):
/// when the peer isn't on the LAN, [push] deposits the pair's delta — every
/// blob AND the manifest encrypted client-side (§7.1, ciphertext-only server)
/// — and the peer's [pull] applies it through the SAME two-way engine
/// semantics as a LAN exchange. Pro-gated (Q1); LAN never touches this path.
class CloudSyncAdapter {
  CloudSyncAdapter(
    this._dao,
    this._store,
    this._engine, {
    required SyncCloudStore cloud,
    required SyncKeyStore keys,
    required String ownFingerprint,
    SyncBlobCipher? cipher,
    String Function(String stored)? resolveRoot,
    bool Function()? cloudSyncFree,
  })  : _cloud = cloud,
        _keys = keys,
        _ownFp = ownFingerprint,
        _cipher = cipher ?? SyncBlobCipher(),
        _resolveRoot = resolveRoot ?? ((s) => s),
        _cloudSyncFree = cloudSyncFree ?? (() => false);

  final SyncDao _dao;
  final ManifestStore _store;
  final SyncEngine _engine;
  final SyncCloudStore _cloud;
  final SyncKeyStore _keys;
  final String _ownFp;
  final SyncBlobCipher _cipher;
  final String Function(String stored) _resolveRoot;

  /// Remote feature flag `cloud_sync_free`: pre-IAP launch period where the
  /// cloud fallback is free for everyone — lifts the Pro tier gate.
  final bool Function() _cloudSyncFree;

  static const int _manifestVersion = 1;

  String _manifestName(String fp) =>
      'm-${fp.replaceAll(RegExp('[^A-Za-z0-9]'), '').padRight(1, 'x')}';

  /// Gate shared by push/pull: pair mode, tier, and key presence.
  Future<(CloudSyncGate, Uint8List?)> _gate(SyncPair pair) async {
    if (pair.mode != 'lanCloud') return (CloudSyncGate.notLanCloud, null);
    if (!_cloudSyncFree()) {
      final beacon = await _cloud.beacon();
      if (beacon.tier != 'pro' && beacon.tier != 'business') {
        return (CloudSyncGate.notPro, null);
      }
    }
    final keyB64 = await _keys.read(SyncEngine.pairKeyStorageKey(pair.id));
    if (keyB64 == null || keyB64.isEmpty) return (CloudSyncGate.noPairKey, null);
    return (CloudSyncGate.ok, Uint8List.fromList(base64Decode(keyB64)));
  }

  // ─── Push: deposit our tree for the offline peer ───

  Future<CloudSyncReport> push(String pairId) async {
    final pair = await _dao.pairById(pairId);
    if (pair == null || pair.paused) {
      return const CloudSyncReport(gate: CloudSyncGate.notLanCloud);
    }
    final (gate, key) = await _gate(pair);
    if (gate != CloudSyncGate.ok) return CloudSyncReport(gate: gate);

    final scan = await _store.rescan(pair);
    final tombs = await _dao.tombstonesFor(pair.id);
    final folderId = await _ensurePairFolder(pair);
    final root = _resolveRoot(pair.rootPath);

    var uploaded = 0;
    final manifestEntries = <Map<String, dynamic>>[];
    for (final e in scan.entries) {
      if (e.isDir) {
        manifestEntries.add({...e.toJson()});
        continue;
      }
      final sha = e.sha256;
      if (sha == null || sha.isEmpty) continue; // unstable — next push
      var ledger = await _dao.blobForContent(pair.id, sha);
      if (ledger == null) {
        final abs = safeSyncJoin(root, e.path);
        if (abs == null) continue;
        final file = File(abs);
        if (!file.existsSync()) continue; // vanished mid-push
        final plain = await file.readAsBytes();
        final cipherBytes = await _cipher.encryptBlob(plain, key!, sha);
        final cSha = c.sha256.convert(cipherBytes).toString();
        final exists = await _cloud.checkExists([cSha]);
        String fileId;
        if (exists[cSha] == true) {
          // Already deposited (an earlier interrupted push) — find its id.
          fileId = (await _findByName(folderId, cSha))?.id ?? '';
          if (fileId.isEmpty) {
            final ref = await _cloud.upload(folderId, cSha, cipherBytes);
            fileId = ref.id;
            uploaded++;
          }
        } else {
          final ref = await _cloud.upload(folderId, cSha, cipherBytes);
          fileId = ref.id;
          uploaded++;
        }
        await _dao.putBlob(SyncCloudBlobsCompanion.insert(
          pairId: pair.id,
          plaintextSha256: sha,
          cloudBlobSha256: cSha,
          fileId: fileId,
          sizeCipher: Value(cipherBytes.length),
        ));
        ledger = await _dao.blobForContent(pair.id, sha);
      }
      manifestEntries.add({...e.toJson(), 'blob': ledger!.cloudBlobSha256});
    }

    // Manifest: replace-by-name (upload new, then retire the previous one).
    final cursor = await _dao.nextCursor(pair.id);
    final manifest = <String, dynamic>{
      'v': _manifestVersion,
      'fp': _ownFp,
      'cursor': cursor,
      'entries': manifestEntries,
      'tombstones': [
        for (final t in tombs) {'path': t.path, 'deletedAtMs': t.deletedAtMs},
      ],
    };
    final encManifest = await _cipher.encryptManifest(
      Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
      key!,
    );
    final name = _manifestName(_ownFp);
    final previous = await _findByName(folderId, name);
    final fresh = await _cloud.upload(folderId, name, encManifest);
    if (previous != null && previous.id != fresh.id) {
      try {
        await _cloud.delete(previous.id);
      } on Object {
        // best-effort retire; the newest-by-name wins on pull
      }
    }
    await _dao.putPeerState(SyncPeerStateCompanion(
      pairId: Value(pair.id),
      lastCloudPushAt: Value(DateTime.now()),
    ));
    debugPrint('[CloudSync] ${pair.id}: pushed $uploaded blob(s) + manifest');
    return CloudSyncReport(gate: CloudSyncGate.ok, uploaded: uploaded);
  }

  // ─── Pull: fetch + apply what the peer deposited ───

  Future<CloudSyncReport> pull(String pairId) async {
    final pair = await _dao.pairById(pairId);
    if (pair == null || pair.paused) {
      return const CloudSyncReport(gate: CloudSyncGate.notLanCloud);
    }
    final (gate, key) = await _gate(pair);
    if (gate != CloudSyncGate.ok) return CloudSyncReport(gate: gate);

    // Cheap beacon: unchanged fingerprint → nothing new server-side.
    final beacon = await _cloud.beacon();
    final state = await _dao.peerState(pair.id);
    if (state?.cloudFingerprint == beacon.fingerprint) {
      return const CloudSyncReport(gate: CloudSyncGate.ok, skipped: true);
    }

    final folderId = await _ensurePairFolder(pair);
    final peerManifestRef =
        await _findByName(folderId, _manifestName(pair.peerFingerprint));
    if (peerManifestRef == null) {
      // Peer never pushed — record the beacon so we don't re-list every poll.
      await _saveFingerprint(pair.id, beacon.fingerprint);
      return const CloudSyncReport(gate: CloudSyncGate.ok, skipped: true);
    }

    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(await _cipher.decryptManifest(
        await _cloud.download(peerManifestRef.id),
        key!,
      ))) as Map<String, dynamic>;
    } on Object catch (e) {
      debugPrint('[CloudSync] ${pair.id}: manifest unreadable: $e');
      return const CloudSyncReport(gate: CloudSyncGate.ok, skipped: true);
    }

    // Rebuild the SAME wire message a LAN announce carries and apply through
    // the engine's two-way semantics (tombstones, LWW, conflict copies).
    final entries = ((manifest['entries'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final blobByPlainSha = <String, String>{
      for (final e in entries)
        if (e['sha256'] is String && e['blob'] is String)
          e['sha256'] as String: e['blob'] as String,
    };
    final msg = SyncManifestMessage(
      pairId: pair.id,
      baseCursor: 0,
      newCursor: (manifest['cursor'] as num?)?.toInt() ?? 0,
      ops: [
        for (final e in entries)
          DeltaOp(
            kind: SyncOpKind.add,
            path: e['path'] as String,
            sha256: e['sha256'] as String?,
            size: (e['size'] as num?)?.toInt(),
            mtimeMs: (e['mtimeMs'] as num?)?.toInt(),
            isDir: (e['isDir'] as bool?) ?? false,
          ),
        for (final t in ((manifest['tombstones'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>())
          DeltaOp(
            kind: SyncOpKind.delete,
            path: t['path'] as String,
            mtimeMs: (t['deletedAtMs'] as num?)?.toInt(),
          ),
      ],
    );
    final ack = await _engine.applySnapshot(pair, msg);

    // Fetch the bytes the apply asked for, decrypt, verify, land atomically.
    final root = _resolveRoot(pair.rootPath);
    var listing = await _cloud.list(folderId);
    var downloaded = 0;
    for (final need in ack.needed) {
      final plainSha = need.sha256;
      if (plainSha == null) continue;
      final cSha = blobByPlainSha[plainSha];
      if (cSha == null) continue; // manifest didn't carry the blob (dir/older)
      var ref = listing.where((r) => r.name == cSha).firstOrNull;
      if (ref == null) {
        listing = await _cloud.list(folderId); // refresh once (racing push)
        ref = listing.where((r) => r.name == cSha).firstOrNull;
        if (ref == null) continue;
      }
      final Uint8List plain;
      try {
        plain = await _cipher.decryptBlob(
          await _cloud.download(ref.id),
          key,
          plainSha,
        );
      } on Object catch (e) {
        debugPrint('[CloudSync] ${pair.id}: blob $cSha unreadable: $e');
        continue;
      }
      if (c.sha256.convert(plain).toString() != plainSha) {
        debugPrint('[CloudSync] ${pair.id}: blob $cSha hash mismatch');
        continue;
      }
      final abs = safeSyncJoin(root, need.path);
      if (abs == null) continue;
      final target = File(abs);
      await target.parent.create(recursive: true);
      final tmp = File('$abs.bishare-cloud.part');
      await tmp.writeAsBytes(plain, flush: true);
      if (target.existsSync()) await target.delete();
      await tmp.rename(abs);
      await _dao.putBlob(SyncCloudBlobsCompanion.insert(
        pairId: pair.id,
        plaintextSha256: plainSha,
        cloudBlobSha256: cSha,
        fileId: ref.id,
        sizeCipher: Value(ref.size),
      ));
      downloaded++;
    }

    await _saveFingerprint(pair.id, beacon.fingerprint);
    await _dao.updatePair(
      pair.toCompanion(true).copyWith(lastSyncAt: Value(DateTime.now())),
    );
    debugPrint(
      '[CloudSync] ${pair.id}: pulled $downloaded blob(s), applied ${ack.applied}',
    );
    return CloudSyncReport(
      gate: CloudSyncGate.ok,
      downloaded: downloaded,
      applied: ack.applied,
    );
  }

  Future<void> _saveFingerprint(String pairId, String fp) =>
      _dao.putPeerState(SyncPeerStateCompanion(
        pairId: Value(pairId),
        cloudFingerprint: Value(fp),
      ));

  Future<String> _ensurePairFolder(SyncPair pair) async {
    final existing = pair.cloudFolderId;
    if (existing != null && existing.isNotEmpty) return existing;
    final id = await _cloud.ensureFolder('.bishare-sync-${pair.id}');
    await _dao.updatePair(
      pair.toCompanion(true).copyWith(cloudFolderId: Value(id)),
    );
    return id;
  }

  Future<CloudFileRef?> _findByName(String folderId, String name) async {
    final listing = await _cloud.list(folderId);
    return listing.where((r) => r.name == name).firstOrNull;
  }
}
