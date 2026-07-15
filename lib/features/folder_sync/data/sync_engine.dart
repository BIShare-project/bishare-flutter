import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/crypto/e2e_crypto.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/sync_tables.dart';
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

/// Fetches a peer's base64 public key (GET /api/v1/info) — needed BEFORE the
/// first encrypted message of a pairing. Injectable; production in
/// `sync_transport.dart`.
typedef PeerInfoFetcher = Future<({String publicKey, String fingerprint})?>
    Function(String host, int port);

/// Persists per-pair secrets (the §7.1 pairKey) OUTSIDE drift — production
/// wraps `flutter_secure_storage` (Keychain/Keystore).
abstract class SyncKeyStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

/// An incoming pairing request awaiting the user's decision (consent sheet).
/// [accept] with the local folder to sync; [reject] or a 30s timeout declines.
class PendingSyncInvite {
  PendingSyncInvite({
    required this.pairId,
    required this.peerAlias,
    required this.peerFingerprint,
    required this.rootName,
  });

  final String pairId;
  final String peerAlias;
  final String peerFingerprint;

  /// The folder name on the inviting device (display + default-folder naming).
  final String rootName;

  final Completer<String?> _decision = Completer<String?>();

  void accept(String rootPath) {
    if (!_decision.isCompleted) _decision.complete(rootPath);
  }

  void reject() {
    if (!_decision.isCompleted) _decision.complete(null);
  }
}

/// Outcome of [SyncEngine.invitePeer].
enum PairInviteOutcome { accepted, rejected }

/// The user's decision on a recorded conflict (§6.1 resolution sheet).
enum ConflictChoice {
  /// Keep the synced winner; my preserved copy goes to the sync-trash.
  keepTheirs,

  /// Restore MY version over the path (it becomes a fresh local edit that
  /// syncs out and wins by recency); the conflict copy goes to the trash.
  keepMine,

  /// Keep both: the conflict copy is renamed to a normal (non-ignored) name so
  /// it syncs to every device alongside the winner.
  keepBoth,
}

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
    this._crypto, {
    required String ownPublicKeyBase64,
    required Directory trashRoot,
    String ownFingerprint = '',
    String ownAlias = '',
    SyncKeyStore? keyStore,
    PeerInfoFetcher? peerInfo,
    ManifestFrameCodec? codec,
    SyncPoster? poster,
    SyncPayloadSender? payloadSender,
    String Function(String stored)? resolveRoot,
    Duration inviteDecisionTimeout = const Duration(seconds: 30),
  }) : _ownPub = ownPublicKeyBase64,
       _ownFingerprint = ownFingerprint,
       _ownAlias = ownAlias,
       _trashRoot = trashRoot,
       _keyStore = keyStore,
       _peerInfo = peerInfo,
       _codec = codec ?? ManifestFrameCodec.ffi(),
       _poster = poster,
       _payloadSender = payloadSender,
       _resolveRoot = resolveRoot ?? _storedAsIs,
       _inviteTimeout = inviteDecisionTimeout;

  static String _storedAsIs(String s) => s;

  final SyncDao _dao;
  final ManifestStore _store;
  final E2ECrypto _crypto;
  final String _ownPub;
  final String _ownFingerprint;
  final String _ownAlias;
  final Directory _trashRoot;
  final SyncKeyStore? _keyStore;
  final PeerInfoFetcher? _peerInfo;
  final ManifestFrameCodec _codec;
  final SyncPoster? _poster;
  final SyncPayloadSender? _payloadSender;
  final String Function(String stored) _resolveRoot;
  final Duration _inviteTimeout;

  /// Filesystem root of [pair] (stored form may be portable/legacy — §sync_roots).
  String _rootOf(SyncPair pair) => _resolveRoot(pair.rootPath);

  final _status = StreamController<SyncPairStatus>.broadcast();
  Stream<SyncPairStatus> get status => _status.stream;

  final _invites = StreamController<PendingSyncInvite>.broadcast();

  /// Incoming pairing requests — the UI shows a consent sheet per event.
  Stream<PendingSyncInvite> get invites => _invites.stream;

  /// The secure-storage key holding a pair's §7.1 pairKey.
  static String pairKeyStorageKey(String pairId) => 'sync_pairkey_$pairId';

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
      // Full snapshot (adds) + our tombstones (delete ops, deletedAtMs riding
      // mtimeMs) — a delete only ever propagates as an explicit tombstone,
      // never inferred from absence (two-way M2, §6.3).
      final tombs = await _dao.tombstonesFor(pairId);
      final msg = SyncManifestMessage(
        pairId: pairId,
        baseCursor: 0, // always a full snapshot until cursor deltas (M2+)
        newCursor: cursor,
        ops: [
          // Hashless files are mid-write (the scanner's stability check
          // deferred them) — announcing them would push half-written bytes.
          // The next watcher debounce / rescan picks them up settled.
          for (final e in scan.entries)
            if (e.isDir || e.sha256 != null)
              DeltaOp(
                kind: SyncOpKind.add,
                path: e.path,
                sha256: e.sha256,
                size: e.size,
                mtimeMs: e.mtimeMs,
                isDir: e.isDir,
              ),
          for (final t in tombs)
            DeltaOp(
              kind: SyncOpKind.delete,
              path: t.path,
              mtimeMs: t.deletedAtMs,
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

  // ─── Pairing (§7.1 bootstrap) ───

  /// Invite [host]:[port] to form a sync pair over [rootPath]. Fetches the
  /// peer's identity, mints the pair's 32-byte AES key, wraps it to the peer's
  /// X25519 key (the same 60-byte envelope as the Rust `wrap_content_key` —
  /// byte-compatible), and sends a consent request. Rows + the stored key are
  /// created ONLY on acceptance — a rejection leaves no trace on either side.
  Future<PairInviteOutcome> invitePeer({
    required String host,
    required int port,
    required String rootPath,
  }) async {
    final poster = _poster;
    final peerInfo = _peerInfo;
    final keys = _keyStore;
    if (poster == null || peerInfo == null || keys == null) {
      throw StateError('sync transport not wired');
    }
    debugPrint('[Sync] invite → GET info $host:$port');
    final info = await peerInfo(host, port);
    if (info == null || info.publicKey.isEmpty) {
      throw StateError('peer info unreachable/keyless at $host:$port');
    }
    debugPrint('[Sync] invite → peer fp=${info.fingerprint}');
    final cipher = await _crypto.deriveSession(info.publicKey);
    if (cipher == null) throw StateError('peer public key is malformed');

    final pairId = _newPairId();
    final pairKey = _randomKey();
    // KEK = the derived session key, so the peer unwraps with its own derive —
    // exactly wrap_content_key/unwrap_content_key semantics (§7.1).
    final wrapped = await cipher.encryptCombined(pairKey);

    final rootName = rootPath
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty)
        .lastOrNull ??
        'Folder';
    final body = await cipher.encryptCombined(Uint8List.fromList(
      _encodeJson({
        'type': 'pairInvite',
        'pairId': pairId,
        'alias': _ownAlias,
        'fingerprint': _ownFingerprint,
        'rootName': rootName,
        'wrappedKey': base64Encode(wrapped),
      }),
    ));
    debugPrint('[Sync] invite → POST /sync (${body.length}B), menunggu consent…');
    final replyBytes = await poster(
      Uri(scheme: 'http', host: host, port: port, path: '/api/v1/sync'),
      body,
      {'x-sync-sender-pub': _ownPub},
    );
    final reply = _decodeJsonMap(await cipher.decryptCombined(replyBytes));
    debugPrint('[Sync] invite → reply: ${reply['type']}');
    if (reply['type'] != 'pairAccept') return PairInviteOutcome.rejected;

    await _dao.createPair(
      SyncPairsCompanion.insert(
        id: pairId,
        rootPath: rootPath,
        peerFingerprint: info.fingerprint,
        peerPublicKey: Value(info.publicKey),
        createdAt: DateTime.now(),
      ),
      pairId,
    );
    await keys.write(pairKeyStorageKey(pairId), base64Encode(pairKey));
    return PairInviteOutcome.accepted;
  }

  String _newPairId() {
    final rnd = _randomKey();
    return base64UrlEncode(rnd.sublist(0, 12)).replaceAll('=', '');
  }

  Uint8List _randomKey() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  // ─── Receiver: wired into TransferServer ───

  /// `POST /api/v1/sync` delegate. [senderPub] comes from the request header;
  /// authenticity is the AEAD itself — a body that decrypts under the key
  /// derived from the pair's stored `peerPublicKey` can only have been produced
  /// by that key's private holder. Returns the encrypted ack, or null → 403.
  ///
  /// Two message shapes share the endpoint: a binary manifest frame (paired
  /// peers) and a JSON pairing message (pre-pair, consent-gated — the decrypted
  /// payload starting with `{` routes here).
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

    final Uint8List plain;
    try {
      plain = await cipher.decryptCombined(Uint8List.fromList(body));
    } on Object {
      return null; // bad AEAD tag — not the presented key's holder
    }

    // Pairing messages are JSON objects tagged type:pairInvite; anything else
    // (binary frames — or the JSON test codec's manifests) falls through to
    // the frame codec.
    if (plain.isNotEmpty && plain.first == 0x7B /* '{' */) {
      try {
        final probe = _decodeJsonMap(plain);
        if (probe['type'] == 'pairInvite') {
          return _handlePairingMessage(senderPub, cipher, plain);
        }
      } on Object {
        // not JSON after all — treat as a frame below
      }
    }

    final SyncManifestMessage msg;
    try {
      msg = await _codec.decode(plain);
    } on Object {
      return null; // malformed frame
    }

    final pair = await _dao.pairById(msg.pairId);
    if (pair == null || pair.paused) return null;
    if (pair.peerPublicKey.isEmpty || pair.peerPublicKey != senderPub) {
      return null; // wire identity must match the pairing-time key
    }

    final SyncAckMessage ack;
    try {
      ack = await _serialize(msg.pairId, () => _applyManifest(pair, msg));
    } on Object catch (e) {
      // An apply failure (unreadable/missing root — e.g. a stale pair whose
      // folder is gone) must answer 403, not bubble into the server as a 500.
      debugPrint('[Sync] apply failed for ${msg.pairId}: $e');
      return null;
    }
    return cipher.encryptCombined(
      Uint8List.fromList(_encodeJson(ack.toJson())),
    );
  }

  /// Consent-gated pairing: surface the invite to the UI and hold the HTTP
  /// exchange open until the user decides (or [_inviteTimeout] rejects). On
  /// accept the pair rows + unwrapped pairKey are stored BEFORE the reply, so
  /// an accepted inviter can sync immediately.
  Future<List<int>?> _handlePairingMessage(
    String senderPub,
    SessionCipher cipher,
    Uint8List plain,
  ) async {
    final Map<String, dynamic> msg;
    try {
      msg = _decodeJsonMap(plain);
    } on Object {
      return null;
    }
    if (msg['type'] != 'pairInvite') return null;
    final pairId = msg['pairId'] as String?;
    final wrappedB64 = msg['wrappedKey'] as String?;
    final keys = _keyStore;
    if (pairId == null || pairId.isEmpty || wrappedB64 == null || keys == null) {
      return null;
    }
    if (await _dao.pairById(pairId) != null) return null; // replayed invite

    final invite = PendingSyncInvite(
      pairId: pairId,
      peerAlias: (msg['alias'] as String?) ?? '',
      peerFingerprint: (msg['fingerprint'] as String?) ?? '',
      rootName: (msg['rootName'] as String?) ?? 'Folder',
    );
    _invites.add(invite);
    final rootPath = await invite._decision.future
        .timeout(_inviteTimeout, onTimeout: () => null);

    if (rootPath == null) {
      return cipher.encryptCombined(
        Uint8List.fromList(_encodeJson({'type': 'pairReject'})),
      );
    }

    // Unwrap the pairKey with OUR derive of the same shared key (§7.1).
    final Uint8List pairKey;
    try {
      pairKey = await cipher.decryptCombined(
        Uint8List.fromList(base64Decode(wrappedB64)),
      );
      if (pairKey.length != 32) throw const FormatException('bad key length');
    } on Object {
      return null;
    }

    // rootPath arrives in STORED form (possibly portable @save/…): resolve to a
    // real filesystem path before touching disk — creating the raw portable
    // string was a relative path on iOS and 500'd every accept (regression of
    // the portable-roots change). Filesystem failures answer 403, never a 500.
    try {
      await Directory(_resolveRoot(rootPath)).create(recursive: true);
    } on Object catch (e) {
      debugPrint('[Sync] pair accept: root create failed: $e');
      return null;
    }
    await _dao.createPair(
      SyncPairsCompanion.insert(
        id: pairId,
        rootPath: rootPath,
        peerFingerprint: invite.peerFingerprint,
        peerPublicKey: Value(senderPub),
        createdAt: DateTime.now(),
      ),
      pairId,
    );
    await keys.write(pairKeyStorageKey(pairId), base64Encode(pairKey));

    return cipher.encryptCombined(
      Uint8List.fromList(_encodeJson({'type': 'pairAccept'})),
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
    return _rootOf(pair);
  }

  /// Apply a peer snapshot that arrived OUTSIDE the LAN exchange — the cloud
  /// pull path (M3). Same two-way semantics, serialized per pair; the caller
  /// (CloudSyncAdapter) downloads whatever the ack reports as needed.
  Future<SyncAckMessage> applySnapshot(SyncPair pair, SyncManifestMessage msg) =>
      _serialize(msg.pairId, () => _applyManifest(pair, msg));

  /// Two-way reconciliation of the announced snapshot against the local tree
  /// (§4.4/§6). Deletes apply ONLY via explicit peer tombstones (absence from
  /// the snapshot never deletes — the peer may simply not have OUR new files);
  /// modify-modify resolves by LWW mtime with a deterministic fingerprint
  /// tiebreak, preserving the overwritten side as a conflict copy; a local
  /// tombstone newer than a remote add suppresses resurrection. Runs inside
  /// the pair's serialize chain.
  Future<SyncAckMessage> _applyManifest(
    SyncPair pair,
    SyncManifestMessage msg,
  ) async {
    if (!msg.isFullSnapshot) {
      // Cursor deltas from a newer peer degrade safely to "send everything".
      return SyncAckMessage(
        pairId: pair.id,
        applied: 0,
        needed: const [],
        cursor: 0,
      );
    }

    // Fresh local truth (self-healing: catches payload arrivals + local edits
    // since the last exchange, and stamps originFp for the conflict rules).
    final local = (await _store.rescan(pair)).entries;
    final localByPath = {for (final e in local) e.path: e};
    final rowByPath = {
      for (final r in await _dao.entriesFor(pair.id)) r.path: r,
    };
    final myTombs = {
      for (final t in await _dao.tombstonesFor(pair.id)) t.path: t,
    };

    final remoteLive = <DeltaOp>[];
    final remoteTombs = <String, int>{}; // path → deletedAtMs
    for (final op in msg.ops) {
      switch (op.kind) {
        case SyncOpKind.add:
          remoteLive.add(op);
        case SyncOpKind.delete:
          remoteTombs[op.path] = op.mtimeMs ?? 0;
        default:
          debugPrint('[Sync] ignoring ${op.kind.wire} op for ${op.path}');
      }
    }

    var applied = 0;
    final needed = <SyncNeededFile>[];
    final renamedFrom = <String>{}; // local paths consumed by a rename

    for (final add in remoteLive) {
      if (add.isDirectory) {
        final dir = _safeDir(_rootOf(pair), add.path);
        if (dir != null && !dir.existsSync()) {
          await dir.create(recursive: true);
          await _upsertEntryRow(pair.id, add, originFp: pair.peerFingerprint);
          applied++;
        }
        continue;
      }

      final mine = localByPath[add.path];
      if (mine == null) {
        // Not on disk here. Our newer tombstone wins (no resurrection) — the
        // peer converges when our tombstone reaches it on our next push.
        final tomb = myTombs[add.path];
        if (tomb != null && tomb.deletedAtMs > (add.mtimeMs ?? 0)) continue;
        if (tomb != null) {
          await _dao.clearTombstone(pair.id, add.path); // re-created remotely
        }
        // Rename detection (zero transfer): the same content vanished remotely
        // under a path we still hold → move ours instead of re-downloading.
        final oldPath = _renameSource(add, remoteTombs, localByPath, renamedFrom);
        if (oldPath != null) {
          final moved = await _applyRename(
            pair,
            DeltaOp(
              kind: SyncOpKind.rename,
              path: oldPath,
              newPath: add.path,
              sha256: add.sha256,
              size: add.size,
              mtimeMs: add.mtimeMs,
              isDir: add.isDir,
            ),
          );
          if (moved) {
            renamedFrom.add(oldPath);
            applied++;
            continue;
          }
        }
        await _needFile(pair.id, add, needed);
        continue;
      }

      if (mine.sha256 == add.sha256) continue; // converged

      // Modify-modify: LWW by mtime, deterministic fingerprint tiebreak (the
      // LARGER fingerprint wins a tie on both sides).
      final remoteWins = (add.mtimeMs ?? 0) > mine.mtimeMs ||
          ((add.mtimeMs ?? 0) == mine.mtimeMs &&
              pair.peerFingerprint.compareTo(_ownFingerprint) > 0);
      if (!remoteWins) continue; // we win — peer converges on reverse push

      // If OUR current version was locally authored (an edit the peer has
      // never seen), preserve it as a conflict copy BEFORE the incoming
      // payload overwrites it (§6.1 — the loser is never discarded).
      if (rowByPath[add.path]?.originFp == _ownFingerprint) {
        await _preserveConflictLoser(pair, add.path);
      }
      await _needFile(pair.id, add, needed);
    }

    for (final entry in remoteTombs.entries) {
      final path = entry.key;
      final deletedAtMs = entry.value;
      if (renamedFrom.contains(path)) continue; // consumed by a rename
      final mine = localByPath[path];
      if (mine == null) {
        // Nothing local — remember the newer tombstone so a stale third push
        // can't resurrect the path later.
        final tomb = myTombs[path];
        if (tomb == null || tomb.deletedAtMs < deletedAtMs) {
          await _dao.putTombstone(SyncTombstonesCompanion.insert(
            pairId: pair.id,
            path: path,
            deletedAtMs: deletedAtMs,
            originFp: Value(pair.peerFingerprint),
          ));
        }
        continue;
      }
      // Modify beats delete (§6.3): a local version newer than the deletion
      // survives, and our next push restores it on the peer.
      if (mine.mtimeMs > deletedAtMs) continue;
      final trashed = await _applyDelete(
        pair,
        DeltaOp(kind: SyncOpKind.delete, path: path, isDir: mine.isDir),
      );
      if (trashed) {
        await _dao.putTombstone(SyncTombstonesCompanion.insert(
          pairId: pair.id,
          path: path,
          deletedAtMs: deletedAtMs,
          originFp: Value(pair.peerFingerprint),
        ));
        applied++;
      }
    }

    await _dao.putPeerState(SyncPeerStateCompanion(
      pairId: Value(pair.id),
      peerCursor: Value(msg.newCursor),
      lastLanSyncAt: Value(DateTime.now()),
    ));
    // The RECEIVER synced too — stamp the pair and tell its UI, so a device
    // that only ever receives (e.g. a phone) still shows "Up to date".
    await _dao.updatePair(
      pair.toCompanion(true).copyWith(lastSyncAt: Value(DateTime.now())),
    );
    _emit(SyncPairStatus(pair.id, SyncPhase.done));

    return SyncAckMessage(
      pairId: pair.id,
      applied: applied,
      needed: needed,
      cursor: msg.newCursor,
    );
  }

  /// Queue a file's bytes and pre-register the expected content hash so (a) the
  /// watcher's echo suppression drops the write event and (b) the next rescan
  /// stamps the row peer-authored instead of locally-authored (payload TTL is
  /// generous — big files take a while to arrive).
  Future<void> _needFile(
    String pairId,
    DeltaOp add,
    List<SyncNeededFile> needed,
  ) async {
    final sha = add.sha256;
    if (sha != null && sha.isNotEmpty) {
      await _dao.expectChange(SyncExpectedChangesRow(
        pairId: pairId,
        path: add.path,
        expectedSha256: sha,
        ttl: const Duration(hours: 24),
      ));
    }
    needed.add(SyncNeededFile(path: add.path, sha256: sha, size: add.size));
  }

  /// The local path whose content matches [add] AND was tombstoned remotely —
  /// i.e. a rename we can replay locally with zero bytes. Skips already-used
  /// sources and hashless entries.
  String? _renameSource(
    DeltaOp add,
    Map<String, int> remoteTombs,
    Map<String, ManifestEntry> localByPath,
    Set<String> used,
  ) {
    final sha = add.sha256;
    if (sha == null || sha.isEmpty) return null;
    for (final tombPath in remoteTombs.keys) {
      if (used.contains(tombPath)) continue;
      final candidate = localByPath[tombPath];
      if (candidate != null &&
          !candidate.isDir &&
          candidate.sha256 == sha &&
          candidate.size == add.size) {
        return tombPath;
      }
    }
    return null;
  }

  /// Save the about-to-be-overwritten local version as a Syncthing-style
  /// sibling `<name>.sync-conflict-<yyyyMMdd-HHmmss>-<alias><.ext>` and record
  /// it in `SyncConflicts`. Conflict copies are default-ignored by the scanner,
  /// so they never sync back (§6.1).
  Future<void> _preserveConflictLoser(SyncPair pair, String relPath) async {
    final src = _safeFile(_rootOf(pair), relPath);
    if (src == null || !await src.exists()) return;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final alias = _ownAlias.isEmpty
        ? _ownFingerprint.replaceAll(RegExp('[^A-Za-z0-9]'), '').padRight(1, 'x')
        : _ownAlias.replaceAll(RegExp(r'[\\/:*?"<>| ]'), '');

    final slash = relPath.lastIndexOf('/');
    final dirPart = slash < 0 ? '' : relPath.substring(0, slash + 1);
    final name = slash < 0 ? relPath : relPath.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    final ext = dot <= 0 ? '' : name.substring(dot);
    final copyRel = '$dirPart$stem.sync-conflict-$stamp-$alias$ext';

    final dst = _safeFile(_rootOf(pair), copyRel);
    if (dst == null) return;
    await src.copy(dst.path);
    await _dao.recordConflict(SyncConflictsCompanion.insert(
      id: _newPairId(),
      pairId: pair.id,
      path: relPath,
      loserCopyPath: copyRel,
      winnerFp: Value(pair.peerFingerprint),
      createdAt: now,
    ));
    debugPrint('[Sync] conflict on $relPath — loser preserved as $copyRel');
  }

  /// Rename/move with no byte transfer. Falls back to "needed" semantics only
  /// via the next exchange if the source is missing (degrades to add — honest,
  /// just less efficient, mirroring manifest_diff's own degradation).
  Future<bool> _applyRename(SyncPair pair, DeltaOp op) async {
    final to = op.newPath;
    if (to == null) return false;
    final root = _rootOf(pair);
    final src = _safeFile(root, op.path);
    final dst = _safeFile(root, to);
    if (src == null || dst == null) return false;
    if (!await src.exists()) return false;
    await Directory(dst.parent.path).create(recursive: true);
    await src.rename(dst.path);
    await _dao.deleteEntry(pair.id, op.path);
    await _upsertEntryRow(
      pair.id,
      op,
      atPath: to,
      originFp: pair.peerFingerprint,
    );
    return true;
  }

  /// Delete = move into `<trash>/<pairId>/<relPath>` (30-day sweep lands in
  /// M2). NEVER unlinks — zero-permanent-loss is the non-negotiable (risk #9).
  Future<bool> _applyDelete(SyncPair pair, DeltaOp op) async {
    final src = _safeFile(_rootOf(pair), op.path);
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
    String? originFp,
  }) => _dao.upsertEntry(SyncEntriesCompanion.insert(
    pairId: pairId,
    path: atPath ?? op.path,
    size: op.size ?? 0,
    mtimeMs: op.mtimeMs ?? 0,
    sha256: Value(op.sha256),
    isDir: Value(op.isDirectory),
    originFp: Value(originFp),
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

  // ─── Conflict resolution (M2c) ───

  /// Apply the user's [choice] to a recorded conflict, then mark it resolved.
  /// Every path stays non-destructive: nothing is unlinked — discarded versions
  /// go to the pair's sync-trash (risk #9).
  Future<void> resolveConflict(String conflictId, ConflictChoice choice) async {
    final conflict = await _dao.conflictById(conflictId);
    if (conflict == null) return;
    final pair = await _dao.pairById(conflict.pairId);
    if (pair == null) {
      await _dao.resolveConflict(conflictId);
      return;
    }
    await _serialize(pair.id, () async {
      final root = _rootOf(pair);
      final copy = _safeFile(root, conflict.loserCopyPath);
      final target = _safeFile(root, conflict.path);

      switch (choice) {
        case ConflictChoice.keepTheirs:
          // The winner already sits at the path — retire my preserved copy.
          if (copy != null && await copy.exists()) {
            await _moveToTrash(pair, conflict.loserCopyPath, copy);
          }
        case ConflictChoice.keepMine:
          if (copy != null && await copy.exists() && target != null) {
            // The overwritten winner is preserved too, then mine comes back as
            // a fresh local edit (newer mtime → wins the next exchange).
            if (await target.exists()) {
              await _moveToTrash(pair, conflict.path, target);
            }
            await Directory(target.parent.path).create(recursive: true);
            await copy.copy(target.path);
            await _moveToTrash(pair, conflict.loserCopyPath, copy);
          }
        case ConflictChoice.keepBoth:
          // Rename the copy OUT of the ignored *.sync-conflict-* namespace so
          // it syncs everywhere alongside the winner.
          if (copy != null && await copy.exists()) {
            final friendly = conflict.loserCopyPath
                .replaceFirst('.sync-conflict-', ' (conflict ')
                .replaceFirst(RegExp(r'(\.[^./]+)?$'), r')$1');
            final dst = _safeFile(root, friendly);
            if (dst != null && !await dst.exists()) {
              await copy.rename(dst.path);
            }
          }
      }
      await _dao.resolveConflict(conflictId);
    });
  }

  Future<void> _moveToTrash(SyncPair pair, String relPath, File src) async {
    final trashed = File(
      '${_trashRoot.path}${Platform.pathSeparator}${pair.id}'
      '${Platform.pathSeparator}${relPath.replaceAll('/', Platform.pathSeparator)}',
    );
    await Directory(trashed.parent.path).create(recursive: true);
    final dst = await _nonClobbering(trashed.path);
    try {
      await src.rename(dst);
    } on FileSystemException {
      await src.copy(dst);
      await src.delete();
    }
  }

  // ─── Maintenance sweeps (M2c) ───

  /// Housekeeping: drop sync-trash items older than [trashTtl] (30 days, §6.3)
  /// and expired tombstones (90 days). Cheap; safe to run at startup and on the
  /// scheduler's periodic tick.
  Future<void> sweepMaintenance({
    Duration trashTtl = const Duration(days: 30),
  }) async {
    for (final pair in await _dao.allPairs()) {
      await _dao.sweepTombstones(pair.id);
    }
    if (!_trashRoot.existsSync()) return;
    final cutoff = DateTime.now().subtract(trashTtl);
    try {
      await for (final ent
          in _trashRoot.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        try {
          if ((await ent.lastModified()).isBefore(cutoff)) {
            await ent.delete();
          }
        } on FileSystemException {
          // Raced/unreadable — the next sweep retries.
        }
      }
    } on FileSystemException {
      // Trash root vanished mid-walk — nothing to sweep.
    }
  }

  Future<void> dispose() async {
    await _status.close();
    await _invites.close();
  }
}
