import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/crypto/e2e_crypto.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/sync_tables.dart';
import '../../../core/sync/delta_engine.dart';
import '../../../core/sync/manifest_store.dart';
import '../../../core/sync/sync_models.dart';
import '../../../core/sync/sync_paths.dart';
import 'sync_wire.dart';

/// Where a sync run currently is — surfaced to the pair card UI.
enum SyncPhase { idle, scanning, exchanging, pushing, done, error }

/// One status tick for a pair (broadcast on [SyncEngine.status]).
class SyncPairStatus {
  const SyncPairStatus(
    this.pairId,
    this.phase, {
    this.pushedFiles = 0,
    this.totalFiles = 0,
    this.message,
  });

  final String pairId;
  final SyncPhase phase;
  final int pushedFiles;
  final int totalFiles;
  final String? message;
}

/// Result of one push run (`syncNow`).
class SyncPushReport {
  const SyncPushReport({
    required this.scanned,
    required this.appliedRemote,
    required this.pushed,
  });

  /// Entries in the local manifest that was announced.
  final int scanned;

  /// Metadata-only ops the peer applied (mkdir/rename/trash).
  final int appliedRemote;

  /// Files whose bytes were pushed because the peer needed them.
  final int pushed;
}

/// POSTs one encrypted sync body to a peer and returns the encrypted response
/// body. Injectable for tests; production wraps dio.
typedef SyncPoster = Future<Uint8List> Function(
  Uri url,
  Uint8List body,
  Map<String, String> headers,
);

/// Pushes the needed files to the peer as a sync payload transfer (the
/// prepare/upload leg with `syncPairId` + per-file `relPath`). Injectable;
/// production wraps `TransferClient.send` (see `sync_transport.dart`).
typedef SyncPayloadSender = Future<void> Function(
  SyncPair pair,
  List<SyncNeededFile> needed,
  String host,
  int port, {
  void Function(int done, int total)? onFile,
});

/// The Tahap 4 folder-sync engine (M1: one-way LAN push, manual trigger).
///
/// Sender side: [syncNow] runs scan → announce full manifest → receive ack →
/// push needed payloads, serialized per pair (single-flight chain, the
/// discovery-service `_serialize` pattern).
///
/// Receiver side: [handleSyncRequest] + [rootForPayload] are wired into
/// `TransferServer` — the server stays transport-only while THIS class owns
/// pair auth, crypto, diffing, and filesystem application. Every apply is
/// non-destructive: a delete moves the file into the pair's sync-trash, never
/// unlinks (risk #9).
class SyncEngine {
  SyncEngine(
    this._dao,
    this._store,
    this._delta,
    this._crypto, {
    required String ownPublicKeyBase64,
    required Directory trashRoot,
    ManifestFrameCodec? codec,
    SyncPoster? poster,
    SyncPayloadSender? payloadSender,
  }) : _ownPub = ownPublicKeyBase64,
       _trashRoot = trashRoot,
       _codec = codec ?? ManifestFrameCodec.ffi(),
       _poster = poster,
       _payloadSender = payloadSender;

  final SyncDao _dao;
  final ManifestStore _store;
  final DeltaEngine _delta;
  final E2ECrypto _crypto;
  final String _ownPub;
  final Directory _trashRoot;
  final ManifestFrameCodec _codec;
  final SyncPoster? _poster;
  final SyncPayloadSender? _payloadSender;

  final _status = StreamController<SyncPairStatus>.broadcast();
  Stream<SyncPairStatus> get status => _status.stream;

  /// Per-pair single-flight chains — every run on a pair is serialized.
  final Map<String, Future<void>> _chains = {};

  Future<T> _serialize<T>(String pairId, Future<T> Function() run) {
    final prev = _chains[pairId] ?? Future<void>.value();
    final completer = Completer<T>();
    _chains[pairId] = prev.then((_) async {
      try {
        completer.complete(await run());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  void _emit(SyncPairStatus s) {
    if (!_status.isClosed) _status.add(s);
  }

  // ─── Sender: push this device's tree to the peer ───

  /// Scan the pair root, announce the manifest to the peer at [host]:[port],
  /// then push whatever bytes the peer asked for. Serialized per pair.
  Future<SyncPushReport> syncNow(
    String pairId, {
    required String host,
    required int port,
  }) => _serialize(pairId, () async {
    final pair = await _dao.pairById(pairId);
    if (pair == null) throw StateError('unknown sync pair $pairId');
    if (pair.paused) throw StateError('sync pair is paused');
    final poster = _poster;
    final sender = _payloadSender;
    if (poster == null || sender == null) {
      throw StateError('sync transport not wired');
    }

    try {
      _emit(SyncPairStatus(pairId, SyncPhase.scanning));
      final scan = await _store.rescan(pair);

      _emit(SyncPairStatus(pairId, SyncPhase.exchanging));
      final cursor = await _dao.nextCursor(pairId);
      final msg = SyncManifestMessage(
        pairId: pairId,
        baseCursor: 0, // M1: always a full snapshot
        newCursor: cursor,
        ops: [
          for (final e in scan.entries)
            DeltaOp(
              kind: SyncOpKind.add,
              path: e.path,
              sha256: e.sha256,
              size: e.size,
              mtimeMs: e.mtimeMs,
              isDir: e.isDir,
            ),
        ],
      );

      final cipher = await _crypto.deriveSession(pair.peerPublicKey);
      if (cipher == null) {
        throw StateError('peer public key is malformed for pair $pairId');
      }
      final body = await cipher.encryptCombined(await _codec.encode(msg));
      final resBytes = await poster(
        Uri(scheme: 'http', host: host, port: port, path: '/api/v1/sync'),
        body,
        {'x-sync-sender-pub': _ownPub},
      );
      final ack = SyncAckMessage.fromJson(
        _decodeJsonMap(await cipher.decryptCombined(resBytes)),
      );

      var pushed = 0;
      if (ack.needed.isNotEmpty) {
        _emit(SyncPairStatus(
          pairId,
          SyncPhase.pushing,
          totalFiles: ack.needed.length,
        ));
        await sender(
          pair,
          ack.needed,
          host,
          port,
          onFile: (done, total) => _emit(SyncPairStatus(
            pairId,
            SyncPhase.pushing,
            pushedFiles: done,
            totalFiles: total,
          )),
        );
        pushed = ack.needed.length;
      }

      await _dao.putPeerState(SyncPeerStateCompanion(
        pairId: Value(pairId),
        lastLanSyncAt: Value(DateTime.now()),
      ));
      await _dao.updatePair(
        (await _dao.pairById(pairId))!
            .toCompanion(true)
            .copyWith(lastSyncAt: Value(DateTime.now())),
      );

      _emit(SyncPairStatus(pairId, SyncPhase.done));
      return SyncPushReport(
        scanned: scan.entries.length,
        appliedRemote: ack.applied,
        pushed: pushed,
      );
    } catch (e) {
      _emit(SyncPairStatus(pairId, SyncPhase.error, message: '$e'));
      rethrow;
    }
  });

  // ─── Receiver: wired into TransferServer ───

  /// `POST /api/v1/sync` delegate. [senderPub] comes from the request header;
  /// authenticity is the AEAD itself — a body that decrypts under the key
  /// derived from the pair's stored `peerPublicKey` can only have been produced
  /// by that key's private holder. Returns the encrypted ack, or null → 403.
  Future<List<int>?> handleSyncRequest(
    String senderPub,
    List<int> body,
  ) async {
    // The pair is identified by the frame's syncId — but decrypting needs the
    // key first, so derive from the PRESENTED pubkey, then verify it matches
    // the pair the frame claims. A stranger's pubkey yields a key that fails
    // AEAD auth on decrypt (they can't encrypt for a pair they're not in).
    final cipher = await _crypto.deriveSession(senderPub);
    if (cipher == null) return null;

    final SyncManifestMessage msg;
    try {
      msg = await _codec.decode(
        await cipher.decryptCombined(Uint8List.fromList(body)),
      );
    } on Object {
      return null; // bad AEAD tag / malformed frame — not a paired sender
    }

    final pair = await _dao.pairById(msg.pairId);
    if (pair == null || pair.paused) return null;
    if (pair.peerPublicKey.isEmpty || pair.peerPublicKey != senderPub) {
      return null; // wire identity must match the pairing-time key
    }

    final ack = await _serialize(msg.pairId, () => _applyManifest(pair, msg));
    return cipher.encryptCombined(
      Uint8List.fromList(_encodeJson(ack.toJson())),
    );
  }

  /// Prepare/upload routing delegate: the pair root for a sync payload session,
  /// or null to reject (unknown pair / wrong sender / paused).
  Future<String?> rootForPayload(String pairId, String senderPublicKey) async {
    final pair = await _dao.pairById(pairId);
    if (pair == null || pair.paused) return null;
    if (pair.peerPublicKey.isEmpty || pair.peerPublicKey != senderPublicKey) {
      return null;
    }
    return pair.rootPath;
  }

  /// Diff the announced snapshot against the local tree and apply what needs no
  /// bytes; report the rest as needed. Runs inside the pair's serialize chain.
  Future<SyncAckMessage> _applyManifest(
    SyncPair pair,
    SyncManifestMessage msg,
  ) async {
    if (!msg.isFullSnapshot) {
      // M1 receivers only speak full snapshots; a cursor delta from a newer
      // peer degrades safely to "send me everything" via an empty ack.
      return SyncAckMessage(
        pairId: pair.id,
        applied: 0,
        needed: const [],
        cursor: 0,
      );
    }

    // Fresh local truth (self-healing: catches files that arrived as payloads
    // since the last exchange), then the SAME shared diff engine as the sender.
    final local = (await _store.rescan(pair)).entries;
    final remote = [
      for (final op in msg.ops)
        if (op.kind == SyncOpKind.add)
          ManifestEntry(
            path: op.path,
            size: op.size ?? 0,
            mtimeMs: op.mtimeMs ?? 0,
            sha256: op.sha256,
            isDir: op.isDirectory,
          ),
    ];
    final ops = await _delta.diff(local: local, remote: remote);

    var applied = 0;
    final needed = <SyncNeededFile>[];
    for (final op in ops) {
      switch (op.kind) {
        case SyncOpKind.add || SyncOpKind.modify when op.isDirectory:
          final dir = _safeDir(pair.rootPath, op.path);
          if (dir != null) {
            await dir.create(recursive: true);
            await _upsertEntryRow(pair.id, op);
            applied++;
          }
        case SyncOpKind.add || SyncOpKind.modify:
          needed.add(SyncNeededFile(
            path: op.path,
            sha256: op.sha256,
            size: op.size,
          ));
        case SyncOpKind.rename:
          if (await _applyRename(pair, op)) applied++;
        case SyncOpKind.delete:
          if (await _applyDelete(pair, op)) applied++;
        case SyncOpKind.unknown:
          debugPrint('[Sync] ignoring unknown op for ${op.path}');
      }
    }

    await _dao.putPeerState(SyncPeerStateCompanion(
      pairId: Value(pair.id),
      peerCursor: Value(msg.newCursor),
      lastLanSyncAt: Value(DateTime.now()),
    ));

    return SyncAckMessage(
      pairId: pair.id,
      applied: applied,
      needed: needed,
      cursor: msg.newCursor,
    );
  }

  /// Rename/move with no byte transfer. Falls back to "needed" semantics only
  /// via the next exchange if the source is missing (degrades to add — honest,
  /// just less efficient, mirroring manifest_diff's own degradation).
  Future<bool> _applyRename(SyncPair pair, DeltaOp op) async {
    final to = op.newPath;
    if (to == null) return false;
    final src = _safeFile(pair.rootPath, op.path);
    final dst = _safeFile(pair.rootPath, to);
    if (src == null || dst == null) return false;
    if (!await src.exists()) return false;
    await Directory(dst.parent.path).create(recursive: true);
    await src.rename(dst.path);
    await _dao.deleteEntry(pair.id, op.path);
    await _upsertEntryRow(pair.id, op, atPath: to);
    return true;
  }

  /// Delete = move into `<trash>/<pairId>/<relPath>` (30-day sweep lands in
  /// M2). NEVER unlinks — zero-permanent-loss is the non-negotiable (risk #9).
  Future<bool> _applyDelete(SyncPair pair, DeltaOp op) async {
    final src = _safeFile(pair.rootPath, op.path);
    if (src == null) return false;
    final srcDir = Directory(src.path);
    final isDir = await srcDir.exists() && (await src.exists()) == false;
    if (!await src.exists() && !isDir) {
      await _dao.deleteEntry(pair.id, op.path);
      return false; // already gone locally — just true-up the manifest row
    }
    final trashed = File(
      '${_trashRoot.path}${Platform.pathSeparator}${pair.id}'
      '${Platform.pathSeparator}${op.path.replaceAll('/', Platform.pathSeparator)}',
    );
    await Directory(trashed.parent.path).create(recursive: true);
    final stamped = await _nonClobbering(trashed.path);
    if (isDir) {
      await srcDir.rename(stamped);
    } else {
      try {
        await src.rename(stamped);
      } on FileSystemException {
        await src.copy(stamped); // EXDEV (trash on another volume)
        await src.delete();
      }
    }
    await _dao.deleteEntry(pair.id, op.path);
    return true;
  }

  Future<void> _upsertEntryRow(
    String pairId,
    DeltaOp op, {
    String? atPath,
  }) => _dao.upsertEntry(SyncEntriesCompanion.insert(
    pairId: pairId,
    path: atPath ?? op.path,
    size: op.size ?? 0,
    mtimeMs: op.mtimeMs ?? 0,
    sha256: Value(op.sha256),
    isDir: Value(op.isDirectory),
  ));

  /// Trash targets never overwrite an earlier trashed generation.
  Future<String> _nonClobbering(String path) async {
    if (!File(path).existsSync() && !Directory(path).existsSync()) return path;
    return '$path.${DateTime.now().millisecondsSinceEpoch}';
  }

  // ─── Path safety (rules shared with TransferServer via safeSyncJoin) ───

  File? _safeFile(String root, String rel) {
    final p = safeSyncJoin(root, rel);
    return p == null ? null : File(p);
  }

  Directory? _safeDir(String root, String rel) {
    final p = safeSyncJoin(root, rel);
    return p == null ? null : Directory(p);
  }

  Uint8List _encodeJson(Map<String, dynamic> m) =>
      Uint8List.fromList(utf8.encode(jsonEncode(m)));

  Map<String, dynamic> _decodeJsonMap(List<int> bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  Future<void> dispose() => _status.close();
}
