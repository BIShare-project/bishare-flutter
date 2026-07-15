import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/sync/manifest_store.dart';
import 'package:bishare/core/sync/sync_models.dart';
import 'package:bishare/features/folder_sync/data/sync_engine.dart';
import 'package:bishare/features/folder_sync/data/sync_wire.dart';
import 'package:bishare/src/rust/api/scanner.dart';
import 'package:crypto/crypto.dart' as c;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real directory walker + hasher standing in for the Rust scanner — same
/// output shape, pure Dart, so the whole engine runs in a unit test.
ScanFn dartScan() {
  return ({required root, required prior, required batchSize, required stabilityMs}) async* {
    final entries = <FfiScanEntry>[];
    final rootDir = Directory(root);
    if (!rootDir.existsSync()) {
      throw StateError('scan root missing: $root');
    }
    for (final ent in rootDir.listSync(recursive: true, followLinks: false)) {
      final rel = ent.path
          .substring(root.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      final stat = ent.statSync();
      if (ent is Directory) {
        entries.add(FfiScanEntry(
          path: rel,
          size: BigInt.zero,
          mtimeMs: stat.modified.millisecondsSinceEpoch,
          isDir: true,
        ));
      } else if (ent is File) {
        entries.add(FfiScanEntry(
          path: rel,
          size: BigInt.from(stat.size),
          mtimeMs: stat.modified.millisecondsSinceEpoch,
          sha256: c.sha256.convert(ent.readAsBytesSync()).toString(),
          isDir: false,
        ));
      }
    }
    yield ScanEvent.batch(entries);
    yield ScanEvent.done(FfiScanStats(
      dirs: BigInt.zero,
      files: BigInt.from(entries.length),
      hashed: BigInt.zero,
      reused: BigInt.zero,
      unstable: BigInt.zero,
      bytesHashed: BigInt.zero,
      errors: BigInt.zero,
    ));
  };
}

/// In-memory [SyncKeyStore] for tests.
class MemKeyStore implements SyncKeyStore {
  final Map<String, String> map = {};
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// One side (device) of a sync test: its DB, root dir, identity, and engine.
class TestDevice {
  TestDevice._(this.name, this.db, this.root, this.trash, this.crypto, this.keys);

  final String name;
  final AppDatabase db;
  final Directory root;
  final Directory trash;
  final E2ECrypto crypto;
  final MemKeyStore keys;
  late SyncEngine engine;

  static Future<TestDevice> create(
    String name, {
    SyncPoster? poster,
    SyncPayloadSender? payloadSender,
    PeerInfoFetcher? peerInfo,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    final base = await Directory.systemTemp.createTemp('bishare_sync_$name');
    final root = Directory('${base.path}/root')..createSync();
    final trash = Directory('${base.path}/trash')..createSync();
    final (crypto, _) = await E2ECrypto.create();
    final dev = TestDevice._(name, db, root, trash, crypto, MemKeyStore());
    dev.engine = SyncEngine(
      db.syncDao,
      ManifestStore(
        db.syncDao,
        ownFingerprint: 'fp-$name',
        scan: dartScan(),
      ),
      crypto,
      ownPublicKeyBase64: crypto.publicKeyBase64,
      ownFingerprint: 'fp-$name',
      ownAlias: name,
      trashRoot: trash,
      keyStore: dev.keys,
      peerInfo: peerInfo,
      codec: ManifestFrameCodec.json(),
      poster: poster,
      payloadSender: payloadSender,
      inviteDecisionTimeout: const Duration(seconds: 2),
    );
    return dev;
  }

  Future<void> close() async {
    await db.close();
    final parent = root.parent;
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  }
}

void main() {
  late TestDevice a; // sender
  late TestDevice b; // receiver
  const pairId = 'pair-test';

  /// Cross-wire [x] to talk to [y]: poster → y's handler; payload sender →
  /// copies bytes into y's root for the pair (standing in for the TCP leg,
  /// which — like the real transfer — does NOT preserve mtimes).
  SyncEngine buildEngine(TestDevice x, TestDevice y) => SyncEngine(
        x.db.syncDao,
        ManifestStore(
          x.db.syncDao,
          ownFingerprint: 'fp-${x.name}',
          scan: dartScan(),
        ),
        x.crypto,
        ownPublicKeyBase64: x.crypto.publicKeyBase64,
        ownFingerprint: 'fp-${x.name}',
        ownAlias: x.name,
        trashRoot: x.trash,
        keyStore: x.keys,
        peerInfo: (host, port) async =>
            (publicKey: y.crypto.publicKeyBase64, fingerprint: 'fp-${y.name}'),
        codec: ManifestFrameCodec.json(),
        poster: (url, body, headers) async {
          final reply = await y.engine.handleSyncRequest(
            headers['x-sync-sender-pub']!,
            body,
          );
          if (reply == null) throw const HttpException('403');
          return Uint8List.fromList(reply);
        },
        payloadSender: (pair, needed, host, port, {onFile}) async {
          final peerPair = await y.db.syncDao.pairById(pair.id);
          var done = 0;
          for (final n in needed) {
            final src = File('${pair.rootPath}/${n.path}');
            if (!src.existsSync()) continue;
            final dst = File('${peerPair!.rootPath}/${n.path}');
            dst.parent.createSync(recursive: true);
            src.copySync(dst.path);
            onFile?.call(++done, needed.length);
          }
        },
        inviteDecisionTimeout: const Duration(seconds: 2),
      );

  /// Two devices, one pair, BOTH directions wired (A⇄B).
  Future<void> setUpPair() async {
    b = await TestDevice.create('b');
    a = await TestDevice.create('a');
    a.engine = buildEngine(a, b);
    b.engine = buildEngine(b, a);

    final now = DateTime(2026, 1, 1);
    // A's view of the pair (peer = B).
    await a.db.syncDao.createPair(
      SyncPairsCompanion.insert(
        id: pairId,
        rootPath: a.root.path,
        peerFingerprint: 'fp-b',
        peerPublicKey: Value(b.crypto.publicKeyBase64),
        createdAt: now,
      ),
      pairId,
    );
    // B's view of the pair (peer = A).
    await b.db.syncDao.createPair(
      SyncPairsCompanion.insert(
        id: pairId,
        rootPath: b.root.path,
        peerFingerprint: 'fp-a',
        peerPublicKey: Value(a.crypto.publicKeyBase64),
        createdAt: now,
      ),
      pairId,
    );
  }

  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('one-way mirror: files + dirs arrive byte-exact', () async {
    await setUpPair();
    File('${a.root.path}/a.txt').writeAsStringSync('hello sync');
    Directory('${a.root.path}/sub').createSync();
    File('${a.root.path}/sub/b.bin')
        .writeAsBytesSync(List<int>.generate(4096, (i) => i % 251));

    final report =
        await a.engine.syncNow(pairId, host: 'loopback', port: 0);

    expect(report.pushed, 2);
    expect(File('${b.root.path}/a.txt').readAsStringSync(), 'hello sync');
    expect(
      c.sha256
          .convert(File('${b.root.path}/sub/b.bin').readAsBytesSync())
          .toString(),
      c.sha256
          .convert(File('${a.root.path}/sub/b.bin').readAsBytesSync())
          .toString(),
    );
  });

  test('second sync is a no-op; rename moves with zero transfer', () async {
    await setUpPair();
    File('${a.root.path}/big.dat')
        .writeAsBytesSync(List<int>.filled(8192, 7));
    await a.engine.syncNow(pairId, host: 'l', port: 0);

    // Converged: nothing needed.
    final again = await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(again.pushed, 0);

    // Rename on A → B applies a move, no bytes cross.
    File('${a.root.path}/big.dat').renameSync('${a.root.path}/renamed.dat');
    final renamed = await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(renamed.pushed, 0, reason: 'rename must move, not re-send');
    expect(renamed.appliedRemote, greaterThan(0));
    expect(File('${b.root.path}/renamed.dat').existsSync(), isTrue);
    expect(File('${b.root.path}/big.dat').existsSync(), isFalse);
  });

  test('delete propagates into sync-trash, never unlinks', () async {
    await setUpPair();
    File('${a.root.path}/doomed.txt').writeAsStringSync('keep me safe');
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(File('${b.root.path}/doomed.txt').existsSync(), isTrue);

    File('${a.root.path}/doomed.txt').deleteSync();
    final report = await a.engine.syncNow(pairId, host: 'l', port: 0);

    expect(report.pushed, 0);
    expect(File('${b.root.path}/doomed.txt').existsSync(), isFalse);
    final trashed = File('${b.trash.path}/$pairId/doomed.txt');
    expect(trashed.existsSync(), isTrue, reason: 'delete = move to trash');
    expect(trashed.readAsStringSync(), 'keep me safe');
  });

  test('two-way: a push never deletes the peer\'s own new files', () async {
    await setUpPair();
    File('${a.root.path}/from-a.txt').writeAsStringSync('A');
    File('${b.root.path}/from-b.txt').writeAsStringSync('B');

    // A pushes: under M1 mirror semantics B's own file would be trashed.
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(File('${b.root.path}/from-b.txt').existsSync(), isTrue,
        reason: 'absence from a snapshot must never delete');
    expect(File('${b.root.path}/from-a.txt').existsSync(), isTrue);

    // B pushes back: both sides converge to the union.
    await b.engine.syncNow(pairId, host: 'l', port: 0);
    expect(File('${a.root.path}/from-b.txt').readAsStringSync(), 'B');
  });

  test('two-way conflict: LWW winner converges, loser kept as conflict copy',
      () async {
    await setUpPair();
    final fileA = File('${a.root.path}/doc.txt')..writeAsStringSync('base');
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    final fileB = File('${b.root.path}/doc.txt');
    expect(fileB.existsSync(), isTrue);

    // Both edit: A first, B later (B is the LWW winner).
    fileA.writeAsStringSync('edit from A');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    fileB.writeAsStringSync('edit from B — newer');

    // A push → B: B's version is newer, B keeps it (no overwrite, no copy).
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(fileB.readAsStringSync(), 'edit from B — newer');

    // B push → A: B wins; A's locally-authored loser is preserved first.
    await b.engine.syncNow(pairId, host: 'l', port: 0);
    expect(fileA.readAsStringSync(), 'edit from B — newer',
        reason: 'both sides converge on the LWW winner');
    final copies = a.root
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.sync-conflict-'))
        .toList();
    expect(copies, hasLength(1), reason: 'loser preserved as a sibling copy');
    expect(copies.single.readAsStringSync(), 'edit from A');

    // The conflict copy is default-ignored: another A push must not spread it.
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(
      b.root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('.sync-conflict-')),
      isEmpty,
    );
  });

  test('two-way: a newer local edit beats an older remote delete', () async {
    await setUpPair();
    File('${a.root.path}/keep.txt').writeAsStringSync('v1');
    await a.engine.syncNow(pairId, host: 'l', port: 0);

    // A deletes; B edits AFTER the deletion moment.
    File('${a.root.path}/keep.txt').deleteSync();
    await a.engine.syncNow(pairId, host: 'l', port: 0); // tombstone minted now
    await Future<void>.delayed(const Duration(milliseconds: 60));
    File('${b.root.path}/keep.txt').writeAsStringSync('v2 — survived');

    // A pushes its tombstone again: B's newer edit must survive (§6.3).
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(File('${b.root.path}/keep.txt').existsSync(), isTrue);

    // B pushes back: the file is restored on A (tombstone cleared).
    await b.engine.syncNow(pairId, host: 'l', port: 0);
    expect(
      File('${a.root.path}/keep.txt').readAsStringSync(),
      'v2 — survived',
    );
  });

  test('two-way: a stale peer cannot resurrect a newer delete', () async {
    await setUpPair();
    final f = File('${a.root.path}/old.txt')..writeAsStringSync('old');
    // Force the file's mtime WELL into the past so the tombstone is younger.
    f.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    final onB = File('${b.root.path}/old.txt');
    expect(onB.existsSync(), isTrue);
    onB.setLastModifiedSync(
      DateTime.now().subtract(const Duration(hours: 1)),
    );

    // A deletes now (tombstone newer than both copies' mtimes).
    File('${a.root.path}/old.txt').deleteSync();
    await a.engine.syncNow(pairId, host: 'l', port: 0);
    expect(onB.existsSync(), isFalse, reason: 'delete propagated');

    // B (holding nothing) pushes — nothing resurrects on A.
    await b.engine.syncNow(pairId, host: 'l', port: 0);
    expect(File('${a.root.path}/old.txt').existsSync(), isFalse);
  });

  test('a stranger (or a paused pair) is rejected', () async {
    await setUpPair();
    File('${a.root.path}/x.txt').writeAsStringSync('x');

    // A stranger with its own keypair presents its own pubkey: decrypt fails →
    // null (the server would 403).
    final (stranger, _) = await E2ECrypto.create();
    final cipher = (await stranger.deriveSession(b.crypto.publicKeyBase64))!;
    final forged = await cipher.encryptCombined(
      Uint8List.fromList(List<int>.filled(64, 1)),
    );
    expect(
      await b.engine.handleSyncRequest(stranger.publicKeyBase64, forged),
      isNull,
    );

    // Pausing the pair on B rejects even the genuine sender.
    await b.db.syncDao.setPaused(pairId, true);
    await expectLater(
      a.engine.syncNow(pairId, host: 'l', port: 0),
      throwsA(isA<HttpException>()),
    );
  });

  test('pairing: invite→accept bootstraps the SAME pairKey both sides, then syncs',
      () async {
    await setUpPair(); // wires poster/payload; we'll pair under a NEW id
    // Point A's peer-info at B and auto-accept invites on B into B's root.
    a.engine = SyncEngine(
      a.db.syncDao,
      ManifestStore(a.db.syncDao, ownFingerprint: 'fp-a', scan: dartScan()),
      a.crypto,
      ownPublicKeyBase64: a.crypto.publicKeyBase64,
      ownFingerprint: 'fp-a',
      ownAlias: 'Device A',
      trashRoot: a.trash,
      keyStore: a.keys,
      peerInfo: (host, port) async =>
          (publicKey: b.crypto.publicKeyBase64, fingerprint: 'fp-b'),
      codec: ManifestFrameCodec.json(),
      poster: (url, body, headers) async {
        final reply = await b.engine.handleSyncRequest(
          headers['x-sync-sender-pub']!,
          body,
        );
        if (reply == null) throw const HttpException('403');
        return Uint8List.fromList(reply);
      },
      payloadSender: (pair, needed, host, port, {onFile}) async {
        // Deliver to the RECEIVER's root for this pair (like the real server).
        final bPair = await b.db.syncDao.pairById(pair.id);
        for (final n in needed) {
          final dst = File('${bPair!.rootPath}/${n.path}');
          dst.parent.createSync(recursive: true);
          File('${a.root.path}/${n.path}').copySync(dst.path);
        }
      },
    );
    final acceptedRoot = Directory('${b.root.parent.path}/accepted-root');
    final sub = b.engine.invites.listen((inv) {
      expect(inv.peerAlias, 'Device A');
      inv.accept(acceptedRoot.path);
    });
    addTearDown(sub.cancel);

    final outcome = await a.engine.invitePeer(
      host: 'loop',
      port: 0,
      rootPath: a.root.path,
    );
    expect(outcome, PairInviteOutcome.accepted);

    // Both sides created the pair and hold the IDENTICAL 32-byte pairKey.
    // (setUpPair pre-created 'pair-test' — the invited pair is the OTHER one.)
    final pairA = (await a.db.syncDao.allPairs())
        .firstWhere((p) => p.id != pairId);
    final pairB = (await b.db.syncDao.allPairs())
        .firstWhere((p) => p.id != pairId);
    expect(pairB.rootPath, acceptedRoot.path);
    expect(pairA.id, pairB.id);
    expect(pairA.peerPublicKey, b.crypto.publicKeyBase64);
    expect(pairB.peerPublicKey, a.crypto.publicKeyBase64);
    final keyA = a.keys.map[SyncEngine.pairKeyStorageKey(pairA.id)];
    final keyB = b.keys.map[SyncEngine.pairKeyStorageKey(pairA.id)];
    expect(keyA, isNotNull);
    expect(keyA, keyB, reason: 'wrap→unwrap must round-trip the same key');
    expect(base64Decode(keyA!).length, 32);

    // The freshly-paired root syncs end-to-end immediately.
    File('${a.root.path}/hello.txt').writeAsStringSync('paired!');
    await a.engine.syncNow(pairA.id, host: 'loop', port: 0);
    expect(
      File('${acceptedRoot.path}/hello.txt').readAsStringSync(),
      'paired!',
    );
  });

  test('pairing: reject leaves no trace on either side', () async {
    await setUpPair();
    a.engine = SyncEngine(
      a.db.syncDao,
      ManifestStore(a.db.syncDao, ownFingerprint: 'fp-a', scan: dartScan()),
      a.crypto,
      ownPublicKeyBase64: a.crypto.publicKeyBase64,
      trashRoot: a.trash,
      keyStore: a.keys,
      peerInfo: (host, port) async =>
          (publicKey: b.crypto.publicKeyBase64, fingerprint: 'fp-b'),
      codec: ManifestFrameCodec.json(),
      poster: (url, body, headers) async {
        final reply = await b.engine.handleSyncRequest(
          headers['x-sync-sender-pub']!,
          body,
        );
        if (reply == null) throw const HttpException('403');
        return Uint8List.fromList(reply);
      },
      payloadSender: (pair, needed, host, port, {onFile}) async {},
    );
    final before = (await a.db.syncDao.allPairs()).length;
    final sub = b.engine.invites.listen((inv) => inv.reject());
    addTearDown(sub.cancel);

    final outcome = await a.engine.invitePeer(
      host: 'loop',
      port: 0,
      rootPath: a.root.path,
    );
    expect(outcome, PairInviteOutcome.rejected);
    expect((await a.db.syncDao.allPairs()).length, before, reason: 'no A row');
    // B stored nothing either (only the pre-existing test pair remains).
    expect(
      b.keys.map.keys.where((k) => k.startsWith('sync_pairkey_')),
      isEmpty,
    );
  });

  test('an exchange against a missing pair root answers 403, not a crash',
      () async {
    await setUpPair();
    File('${a.root.path}/x.txt').writeAsStringSync('x');
    // Simulate the stale-pair case: B's folder vanished after pairing.
    b.root.deleteSync(recursive: true);

    await expectLater(
      a.engine.syncNow(pairId, host: 'l', port: 0),
      throwsA(isA<HttpException>()), // the 403 surfaces as a clean sender error
    );
    b.root.createSync(); // restore for tearDown
  });

  test('malicious traversal paths are ignored, not applied', () async {
    await setUpPair();
    // Craft a manifest claiming a file above the root; B must skip it.
    final cipher = (await a.crypto.deriveSession(b.crypto.publicKeyBase64))!;
    final evil = SyncManifestMessage(
      pairId: pairId,
      baseCursor: 0,
      newCursor: 1,
      ops: const [
        DeltaOp(
          kind: SyncOpKind.add,
          path: '../evil.txt',
          sha256: 'aa',
          size: 2,
          mtimeMs: 1,
          isDir: false,
        ),
        DeltaOp(kind: SyncOpKind.add, path: 'ok-dir', isDir: true, mtimeMs: 1, size: 0),
      ],
    );
    final body = await cipher.encryptCombined(
      await ManifestFrameCodec.json().encode(evil),
    );
    final reply =
        await b.engine.handleSyncRequest(a.crypto.publicKeyBase64, body);
    expect(reply, isNotNull);

    // The traversal target was NOT created outside the root...
    expect(File('${b.root.parent.path}/evil.txt').existsSync(), isFalse);
    // ...but it IS reported as needed (path validation happens at apply/save,
    // and the payload leg re-validates before writing).
    expect(Directory('${b.root.path}/ok-dir').existsSync(), isTrue);
  });
}

// Small JSON helpers (avoid importing dart:convert twice under test names).
List<Map<String, dynamic>> jsonDecodeList(String s) =>
    (const JsonDecoder().convert(s) as List).cast<Map<String, dynamic>>();
String jsonEncodeList(List<Map<String, dynamic>> l) =>
    const JsonEncoder().convert(l);
