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
    String ownFingerprint = '',
    String ownAlias = '',
    SyncKeyStore? keyStore,
    PeerInfoFetcher? peerInfo,
    ManifestFrameCodec? codec,
    SyncPoster? poster,
    SyncPayloadSender? payloadSender,
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
       _inviteTimeout = inviteDecisionTimeout;

  final SyncDao _dao;
  final ManifestStore _store;
  final DeltaEngine _delta;
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
  final Duration _inviteTimeout;

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
    final info = await peerInfo(host, port);
    if (info == null || info.publicKey.isEmpty) {
      throw StateError('peer does not expose a public key');
    }
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
    final replyBytes = await poster(
      Uri(scheme: 'http', host: host, port: port, path: '/api/v1/sync'),
      body,
      {'x-sync-sender-pub': _ownPub},
    );
    final reply = _decodeJsonMap(await cipher.decryptCombined(replyBytes));
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

    final ack = await _serialize(msg.pairId, () => _applyManifest(pair, msg));
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

    await Directory(rootPath).create(recursive: true);
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

  Future<void> dispose() async {
    await _status.close();
    await _invites.close();
  }
}
