import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/core/rust/rust_facade.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/storage/vault_tables.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_downloads.dart';
import 'package:bishare/features/vault/data/vault_file_work.dart';
import 'package:bishare/features/vault/data/vault_files.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_meta.dart';
import 'package:bishare/features/vault/data/vault_sync.dart';
import 'package:bishare/features/vault/presentation/drive/drive_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// The fixes from the Drive audit of 2026-10-21 that unit tests can hold:
/// downloads checked against size and hash, compression off the screen's
/// isolate, the trash (restore what went with a folder, never delete what
/// is live), search in Trash, and file names that are safe on disk.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  late final bool rust;
  setUpAll(() async => rust = await initRustForTests());

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('vault-audit'));
  tearDown(() => tmp.delete(recursive: true));

  group('VaultFileWork', () {
    Uint8List text(int n) => Uint8List.fromList(List.generate(n, (i) => 'drive '.codeUnitAt(i % 6)));

    test('one read gives the hash and size, and a compressed copy only when it is worth it', () async {
      final plain = File('${tmp.path}/a.txt')..writeAsBytesSync(text(300000));
      final z = '${tmp.path}/a.z';
      final snap = await VaultFileWork.snapshot(plain.path, zPath: z);
      expect(snap.size, 300000);
      expect(snap.hash, sha256.convert(plain.readAsBytesSync()).bytes);
      expect(snap.compressed, isTrue);
      expect(File(z).existsSync(), isTrue);
      expect(File('$z.tmp').existsSync(), isFalse, reason: 'written under another name, then renamed');

      final noise = File('${tmp.path}/b.bin')
        ..writeAsBytesSync(Uint8List.fromList(List.generate(200000, (_) => Random().nextInt(256))));
      final z2 = '${tmp.path}/b.z';
      final snap2 = await VaultFileWork.snapshot(noise.path, zPath: z2);
      expect(snap2.compressed, isFalse);
      expect(File(z2).existsSync(), isFalse);
      final streamed = await VaultFileWork.snapshot(noise.path);
      expect(streamed.hash, snap2.hash);
      expect(streamed.size, 200000);
    });

    test('inflate gives exactly the stored size and hash, or nothing', () async {
      final bytes = text(500000);
      final hash = Uint8List.fromList(sha256.convert(bytes).bytes);
      final plain = File('${tmp.path}/c.txt')..writeAsBytesSync(bytes);
      final z = '${tmp.path}/c.z';
      await VaultFileWork.snapshot(plain.path, zPath: z);
      final out = '${tmp.path}/c.out';
      await VaultFileWork.inflate(z, out, bytes.length, hash);
      expect(File(out).readAsBytesSync(), bytes);
      await expectLater(VaultFileWork.inflate(z, out, bytes.length - 1, hash), throwsFormatException);
      await expectLater(VaultFileWork.inflate(z, out, bytes.length + 1, hash), throwsFormatException);
      final wrong = Uint8List.fromList(hash)..[0] ^= 1;
      await expectLater(VaultFileWork.inflate(z, out, bytes.length, wrong), throwsFormatException);
    });

    test('a decompression bomb stops at the size the metadata gives', () async {
      final zeros = File('${tmp.path}/zeros')..writeAsBytesSync(Uint8List(64 << 20));
      final z = '${tmp.path}/zeros.z';
      await VaultFileWork.snapshot(zeros.path, zPath: z);
      expect(File(z).lengthSync(), lessThan(1 << 20));
      await expectLater(VaultFileWork.inflate(z, '${tmp.path}/bomb.out', 1000, null), throwsFormatException);
      expect(File('${tmp.path}/bomb.out').lengthSync(), lessThan(1 << 20));
    });

    test('raw DEFLATE from the Rust core and from dart:io open in both', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final bytes = text(200000);
      final hash = Uint8List.fromList(sha256.convert(bytes).bytes);
      final fromRust = File('${tmp.path}/r.z')..writeAsBytesSync(Rust.vaultDeflateRaw(bytes));
      await VaultFileWork.inflate(fromRust.path, '${tmp.path}/r.out', bytes.length, hash);
      expect(File('${tmp.path}/r.out').readAsBytesSync(), bytes);
      final plain = File('${tmp.path}/d.txt')..writeAsBytesSync(bytes);
      await VaultFileWork.snapshot(plain.path, zPath: '${tmp.path}/d.z');
      expect(Rust.vaultInflateRaw(File('${tmp.path}/d.z').readAsBytesSync(), bytes.length), bytes);
    });

    test('a file cut short, or changed, is refused', () async {
      final bytes = text(3 << 20);
      final hash = Uint8List.fromList(sha256.convert(bytes).bytes);
      final f = File('${tmp.path}/e.bin')..writeAsBytesSync(bytes);
      await VaultFileWork.verify(f.path, bytes.length, hash);
      f.writeAsBytesSync(bytes.sublist(0, 2 << 20));
      await expectLater(VaultFileWork.verify(f.path, bytes.length, hash), throwsFormatException);
      f.writeAsBytesSync(Uint8List.fromList(bytes)..[5] ^= 1);
      await expectLater(VaultFileWork.verify(f.path, bytes.length, hash), throwsFormatException);
    });
  });

  test('names on disk: no separators, nothing Windows refuses, never "." or ".."', () {
    expect(VaultDownloads.safeName('..'), '_');
    expect(VaultDownloads.safeName('.'), '_');
    expect(VaultDownloads.safeName('a/../b'), 'a_.._b');
    expect(VaultDownloads.safeName(r'c:\x?*'), 'c__x__');
    expect(VaultDownloads.safeName('  '), 'file');
    expect(VaultDownloads.safeName('Report.pdf'), 'Report.pdf');
  });

  group('the trash', () {
    late AppDatabase db;
    late VaultKeyStore keys;
    late _Ops api;
    late VaultFiles files;
    const vaultId = 'efgtkgwp3kofr2frtdwl7llgbe';
    late Uint8List vk;
    var seq = 0;

    Future<void> add(String id, String name, {String? parent, bool dir = false, int? trashed}) async {
      final meta = VaultMeta(
        kind: dir ? 'dir' : 'file',
        name: name,
        parent: parent,
        mtimeMs: 1,
        size: dir ? null : 3,
        mime: dir ? null : 'text/plain',
        fileKey: dir ? null : Rust.vaultGenerateFileKey(),
        hash: dir ? null : Uint8List(32),
      );
      await db.vaultDao.upsertObjects([
        VaultObjectsCompanion.insert(
          id: id,
          parent: Value(parent),
          name: name,
          kind: dir ? 'dir' : 'file',
          size: Value(dir ? null : 3),
          mtime: 1,
          seq: ++seq,
          createdAt: 1,
          trashedAt: Value(trashed),
          encMeta: VaultMetaCodec.seal(vk, vaultId, id, meta),
        ),
      ]);
    }

    setUp(() async {
      if (!rust) return;
      FlutterSecureStorage.setMockInitialValues({});
      db = AppDatabase(NativeDatabase.memory());
      keys = VaultKeyStore();
      vk = Rust.vaultGenerateKey();
      await keys.saveVault(vaultId: vaultId);
      await keys.saveVaultKey(vk);
      api = _Ops(keys);
      files = VaultFiles(api: api, keys: keys, dao: db.vaultDao, sync: _NoSync(api, keys, db.vaultDao));
    });
    tearDown(() async {
      if (rust) await db.close();
    });

    List<String> sent(String type) => [
      for (final op in api.sent)
        if (op['type'] == type) op['objectId'] as String,
    ];

    test('delete for good: only what is in the trash; something live inside is kept, at the top', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final id = [for (var i = 0; i < 6; i++) Rust.vaultGenerateObjectId()];
      await add(id[0], 'Old', dir: true, trashed: 1000);
      await add(id[1], 'a.txt', parent: id[0], trashed: 1000);
      await add(id[2], 'Sub', parent: id[0], dir: true, trashed: 1000);
      await add(id[3], 'b.txt', parent: id[2], trashed: 1000);
      await add(id[4], 'added later.txt', parent: id[2]); // live, from another device
      await add(id[5], 'live.txt'); // not in the trash at all
      await files.deleteForGood([id[0], id[5]]);
      expect(sent('delete').toSet(), {id[0], id[1], id[2], id[3]});
      expect(sent('delete').last, id[0], reason: 'contents first, the folder last');
      expect(sent('meta'), [id[4]], reason: 'moved to the top of the Drive, not deleted');
      expect(sent('delete'), isNot(contains(id[5])));
    });

    test('restore brings back what went with the folder, even in a later call, not what went before', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final id = [for (var i = 0; i < 4; i++) Rust.vaultGenerateObjectId()];
      await add(id[0], 'Big', dir: true, trashed: 100000);
      await add(id[1], 'first call.txt', parent: id[0], trashed: 100000);
      await add(id[2], 'later call.txt', parent: id[0], trashed: 130000);
      await add(id[3], 'trashed before.txt', parent: id[0], trashed: 40000);
      await files.restore([id[0]]);
      expect(sent('restore').toSet(), {id[0], id[1], id[2]});
    });

    test('search in Trash finds only what is in the trash', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      await add(Rust.vaultGenerateObjectId(), 'Report.pdf');
      await add(Rust.vaultGenerateObjectId(), 'report old.txt', trashed: 5);
      await add(Rust.vaultGenerateObjectId(), 'Отчёт.txt');
      final c = DriveController(db.vaultDao)
        ..setView(DriveView.trash)
        ..setQuery('REPORT');
      expect((await c.items().first).map((o) => o.name), ['report old.txt']);
      c
        ..setView(DriveView.files)
        ..setQuery('отчёт');
      expect((await c.items().first).map((o) => o.name), ['Отчёт.txt'], reason: 'any case, any language');
    });
  });
}

class _Ops extends VaultApi {
  _Ops(super.keys);

  final sent = <Map<String, dynamic>>[];

  @override
  Future<({int seq, List<Map<String, dynamic>> results})> ops(String vaultId, List<Map<String, dynamic>> ops) async {
    sent.addAll(ops);
    return (seq: sent.length, results: [for (final op in ops) {'ok': true, 'opId': op['opId']}]);
  }
}

class _NoSync extends VaultSync {
  _NoSync(VaultApi api, VaultKeyStore keys, VaultDao dao) : super(api: api, keys: keys, dao: dao);

  @override
  Future<void> pull() async {}
}
