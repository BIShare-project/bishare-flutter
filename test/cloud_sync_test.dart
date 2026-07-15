import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/features/folder_sync/data/cloud_store.dart';
import 'package:bishare/features/folder_sync/data/cloud_sync_adapter.dart';
import 'package:bishare/features/folder_sync/data/sync_crypto.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/sync/manifest_store.dart';
import 'package:crypto/crypto.dart' as c;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'sync_engine_test.dart' show TestDevice, dartScan;

/// In-memory drive backend: names, ids, bytes — and a fingerprint that moves
/// on every write (like sync-status reacting to uploads).
class MemCloudStore implements SyncCloudStore {
  final Map<String, String> folders = {}; // name → id
  final Map<String, Map<String, (String id, Uint8List bytes)>> objects = {};
  String tier = 'pro';
  int _seq = 0;
  int _version = 0;

  @override
  Future<String> ensureFolder(String name) async =>
      folders.putIfAbsent(name, () => 'folder-${_seq++}');

  Map<String, (String, Uint8List)> _folder(String folderId) =>
      objects.putIfAbsent(folderId, () => {});

  @override
  Future<Map<String, bool>> checkExists(List<String> hashes) async {
    final all = {
      for (final f in objects.values)
        for (final name in f.keys) name,
    };
    return {for (final h in hashes) h: all.contains(h)};
  }

  @override
  Future<CloudFileRef> upload(
    String folderId,
    String name,
    Uint8List bytes,
  ) async {
    final id = 'file-${_seq++}';
    _folder(folderId)[name] = (id, Uint8List.fromList(bytes));
    _version++;
    return CloudFileRef(id: id, name: name, size: bytes.length);
  }

  @override
  Future<List<CloudFileRef>> list(String folderId) async => [
        for (final e in _folder(folderId).entries)
          CloudFileRef(id: e.value.$1, name: e.key, size: e.value.$2.length),
      ];

  @override
  Future<Uint8List> download(String fileId) async {
    for (final f in objects.values) {
      for (final v in f.values) {
        if (v.$1 == fileId) return v.$2;
      }
    }
    throw StateError('no such file $fileId');
  }

  @override
  Future<void> delete(String fileId) async {
    for (final f in objects.values) {
      f.removeWhere((_, v) => v.$1 == fileId);
    }
    _version++;
  }

  @override
  Future<CloudSyncBeacon> beacon() async =>
      CloudSyncBeacon(fingerprint: 'v$_version', tier: tier);

  /// Every stored byte-blob (for the ciphertext-only assertion).
  Iterable<Uint8List> get allBytes =>
      objects.values.expand((f) => f.values.map((v) => v.$2));
}

void main() {
  group('SyncBlobCipher', () {
    final cipher = SyncBlobCipher();
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i ^ 0x5a));

    test('deterministic: same content → identical ciphertext; round-trips',
        () async {
      final plain = Uint8List.fromList(
        List<int>.generate(300 * 1024, (i) => i % 251), // spans 2 chunks
      );
      final sha = c.sha256.convert(plain).toString();
      final c1 = await cipher.encryptBlob(plain, key, sha);
      final c2 = await cipher.encryptBlob(plain, key, sha);
      expect(c.sha256.convert(c1), c.sha256.convert(c2),
          reason: 'content-addressed name must be stable');
      expect(await cipher.decryptBlob(c1, key, sha), plain);
    });

    test('distinct content under one key → distinct ciphertext prefix (nonce)',
        () async {
      final a = Uint8List.fromList(utf8.encode('AAA'));
      final b = Uint8List.fromList(utf8.encode('BBB'));
      final ca = await cipher.encryptBlob(
          a, key, c.sha256.convert(a).toString());
      final cb = await cipher.encryptBlob(
          b, key, c.sha256.convert(b).toString());
      // First frame nonce lives at bytes [4..16).
      expect(ca.sublist(4, 16), isNot(cb.sublist(4, 16)));
    });

    test('wrong key / tampered byte fails closed', () async {
      final plain = Uint8List.fromList(utf8.encode('secret'));
      final sha = c.sha256.convert(plain).toString();
      final enc = await cipher.encryptBlob(plain, key, sha);
      final wrong = Uint8List.fromList(List<int>.filled(32, 9));
      expect(
        () => cipher.decryptBlob(enc, wrong, sha),
        throwsA(anything),
      );
      final tampered = Uint8List.fromList(enc)..[enc.length - 1] ^= 0xff;
      expect(() => cipher.decryptBlob(tampered, key, sha), throwsA(anything));
    });

    test('manifest round-trips; random nonce (two encrypts differ)', () async {
      final plain = Uint8List.fromList(utf8.encode('{"v":1}'));
      final e1 = await cipher.encryptManifest(plain, key);
      final e2 = await cipher.encryptManifest(plain, key);
      expect(e1, isNot(e2));
      expect(await cipher.decryptManifest(e1, key), plain);
    });
  });

  group('CloudSyncAdapter (loopback A → cloud → B)', () {
    late TestDevice a;
    late TestDevice b;
    late MemCloudStore cloud;
    late CloudSyncAdapter adapterA;
    late CloudSyncAdapter adapterB;
    const pairId = 'pair-cloud';
    final pairKey = base64Encode(List<int>.generate(32, (i) => 200 - i));

    CloudSyncAdapter buildAdapter(TestDevice d) => CloudSyncAdapter(
          d.db.syncDao,
          ManifestStore(
            d.db.syncDao,
            ownFingerprint: 'fp-${d.name}',
            scan: dartScan(),
          ),
          d.engine,
          cloud: cloud,
          keys: d.keys,
          ownFingerprint: 'fp-${d.name}',
        );

    setUp(() async {
      cloud = MemCloudStore();
      // No LAN wiring at all — the cloud is the only path between A and B.
      a = await TestDevice.create('a');
      b = await TestDevice.create('b');
      for (final (dev, peer) in [(a, b), (b, a)]) {
        await dev.db.syncDao.createPair(
          SyncPairsCompanion.insert(
            id: pairId,
            rootPath: dev.root.path,
            peerFingerprint: 'fp-${peer.name}',
            peerPublicKey: Value(peer.crypto.publicKeyBase64),
            mode: const Value('lanCloud'),
            createdAt: DateTime(2026, 1, 1),
          ),
          pairId,
        );
        await dev.keys.write('sync_pairkey_$pairId', pairKey);
      }
      adapterA = buildAdapter(a);
      adapterB = buildAdapter(b);
    });

    tearDown(() async {
      await a.close();
      await b.close();
    });

    test('store-and-forward: push on A, pull on B — byte-exact, server-blind',
        () async {
      File('${a.root.path}/notes.txt')
          .writeAsStringSync('meet at the usual place');
      Directory('${a.root.path}/pics').createSync();
      final big = Uint8List.fromList(
        List<int>.generate(300 * 1024, (i) => (i * 7) % 251),
      );
      File('${a.root.path}/pics/photo.bin').writeAsBytesSync(big);

      final pushed = await adapterA.push(pairId);
      expect(pushed.gate, CloudSyncGate.ok);
      expect(pushed.uploaded, 2);

      // The server holds ONLY ciphertext: no stored object contains the
      // plaintext, and blob names are ciphertext hashes.
      const secret = 'meet at the usual place';
      for (final bytes in cloud.allBytes) {
        expect(utf8.decode(bytes, allowMalformed: true).contains(secret),
            isFalse);
      }

      final pulled = await adapterB.pull(pairId);
      expect(pulled.gate, CloudSyncGate.ok);
      expect(pulled.downloaded, 2);
      expect(
        File('${b.root.path}/notes.txt').readAsStringSync(),
        secret,
      );
      expect(
        c.sha256
            .convert(File('${b.root.path}/pics/photo.bin').readAsBytesSync())
            .toString(),
        c.sha256.convert(big).toString(),
      );

      // Second pull: unchanged beacon → skipped, nothing re-fetched.
      final again = await adapterB.pull(pairId);
      expect(again.skipped, isTrue);
    });

    test('a delete travels the cloud as a tombstone', () async {
      final f = File('${a.root.path}/doomed.txt')..writeAsStringSync('bye');
      f.setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 5)),
      );
      await adapterA.push(pairId);
      await adapterB.pull(pairId);
      expect(File('${b.root.path}/doomed.txt').existsSync(), isTrue);

      File('${a.root.path}/doomed.txt').deleteSync();
      await adapterA.push(pairId);
      await adapterB.pull(pairId);

      expect(File('${b.root.path}/doomed.txt').existsSync(), isFalse);
      final trash = Directory('${b.trash.path}/$pairId');
      expect(
        trash.existsSync() &&
            trash.listSync(recursive: true).whereType<File>().isNotEmpty,
        isTrue,
        reason: 'cloud deletes are as non-destructive as LAN ones',
      );
    });

    test('free tier is gated off; lanOnly mode never touches the cloud',
        () async {
      cloud.tier = 'free';
      File('${a.root.path}/x.txt').writeAsStringSync('x');
      expect((await adapterA.push(pairId)).gate, CloudSyncGate.notPro);
      expect(cloud.objects, isEmpty, reason: 'no bytes may leave on free');

      // The remote `cloud_sync_free` flag (admin-controlled launch period)
      // lifts the tier gate — same free tier, push now goes through.
      final freeAdapter = CloudSyncAdapter(
        a.db.syncDao,
        ManifestStore(
          a.db.syncDao,
          ownFingerprint: 'fp-${a.name}',
          scan: dartScan(),
        ),
        a.engine,
        cloud: cloud,
        keys: a.keys,
        ownFingerprint: 'fp-${a.name}',
        cloudSyncFree: () => true,
      );
      expect((await freeAdapter.push(pairId)).gate, CloudSyncGate.ok);
      expect(cloud.objects, isNotEmpty);
      cloud.objects.clear();

      cloud.tier = 'pro';
      await a.db.syncDao.updatePair(
        (await a.db.syncDao.pairById(pairId))!
            .toCompanion(true)
            .copyWith(mode: const Value('lanOnly')),
      );
      expect((await adapterA.push(pairId)).gate, CloudSyncGate.notLanCloud);
      expect(cloud.objects, isEmpty,
          reason: 'lanOnly must make zero cloud calls for content');
    });

    test('idempotent re-push: unchanged content uploads nothing new', () async {
      File('${a.root.path}/same.txt').writeAsStringSync('stable');
      final first = await adapterA.push(pairId);
      expect(first.uploaded, 1);
      final second = await adapterA.push(pairId);
      expect(second.uploaded, 0, reason: 'ledger + check-exists dedup');
    });
  });
}
