import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/sync/manifest_store.dart';
import 'package:bishare/src/rust/api/scanner.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a fake `scan_and_hash` that streams one batch of [entries] then Done —
/// lets us drive [ManifestStore] without a native library.
ScanFn _fakeScan(List<FfiScanEntry> entries) {
  return ({required root, required prior, required batchSize, required stabilityMs}) async* {
    yield ScanEvent.batch(entries);
    yield ScanEvent.done(FfiScanStats(
      dirs: BigInt.zero,
      files: BigInt.from(entries.where((e) => !e.isDir).length),
      hashed: BigInt.zero,
      reused: BigInt.zero,
      unstable: BigInt.zero,
      bytesHashed: BigInt.zero,
      errors: BigInt.zero,
    ));
  };
}

FfiScanEntry _f(String path, {int size = 1, int mtime = 1, String? sha, bool dir = false}) =>
    FfiScanEntry(
      path: path,
      size: BigInt.from(size),
      mtimeMs: mtime,
      sha256: sha,
      isDir: dir,
    );

Future<AppDatabase> _dbWithPair() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.syncDao.createPair(
    SyncPairsCompanion.insert(
      id: 'p',
      rootPath: '/root',
      peerFingerprint: 'fp',
      createdAt: DateTime(2026, 1, 1),
    ),
    'p',
  );
  return db;
}

Future<SyncPair> _pair(AppDatabase db) async => (await db.syncDao.pairById('p'))!;

void main() {
  test('rescan filters ignores, persists survivors, reports changed', () async {
    final db = await _dbWithPair();
    final store = ManifestStore(
      db.syncDao,
      scan: _fakeScan([
        _f('a.txt', size: 5, mtime: 1000, sha: 'h1'),
        _f('sub', dir: true),
        _f('sub/b.txt', size: 7, mtime: 1100, sha: 'h2'),
        _f('.DS_Store', size: 3, mtime: 1, sha: 'junk'), // default-ignored
      ]),
    );

    final res = await store.rescan(await _pair(db));

    // The ignored file is gone from the returned manifest and never persisted.
    expect(res.changed, isTrue);
    expect(res.entries.map((e) => e.path), containsAll(['a.txt', 'sub', 'sub/b.txt']));
    expect(res.entries.any((e) => e.path == '.DS_Store'), isFalse);

    final rows = await db.syncDao.entriesFor('p');
    expect(rows.map((r) => r.path).toSet(), {'a.txt', 'sub', 'sub/b.txt'});
    expect(rows.firstWhere((r) => r.path == 'sub').isDir, isTrue);

    await db.close();
  });

  test('an unchanged rescan writes nothing and reports no change', () async {
    final db = await _dbWithPair();
    final entries = [
      _f('a.txt', size: 5, mtime: 1000, sha: 'h1'),
      _f('sub/b.txt', size: 7, mtime: 1100, sha: 'h2'),
    ];
    final store = ManifestStore(db.syncDao, scan: _fakeScan(entries));

    expect((await store.rescan(await _pair(db))).changed, isTrue); // first scan
    expect((await store.rescan(await _pair(db))).changed, isFalse); // identical → no-op

    await db.close();
  });

  test('rescan deletes vanished paths and updates modified ones', () async {
    final db = await _dbWithPair();
    // First scan seeds two files.
    await ManifestStore(db.syncDao, scan: _fakeScan([
      _f('a.txt', size: 5, mtime: 1000, sha: 'h1'),
      _f('gone.txt', size: 9, mtime: 500, sha: 'g'),
    ])).rescan(await _pair(db));

    // Second scan: gone.txt vanished; a.txt was modified (new mtime + hash).
    final res = await ManifestStore(db.syncDao, scan: _fakeScan([
      _f('a.txt', size: 6, mtime: 2000, sha: 'h1b'),
    ])).rescan(await _pair(db));

    expect(res.changed, isTrue);
    final rows = await db.syncDao.entriesFor('p');
    expect(rows.map((r) => r.path), ['a.txt']); // gone.txt pruned
    final a = rows.single;
    expect(a.mtimeMs, 2000);
    expect(a.sha256, 'h1b');

    await db.close();
  });

  test('current() reads the persisted manifest back as ManifestEntry', () async {
    final db = await _dbWithPair();
    await db.syncDao.upsertEntry(SyncEntriesCompanion.insert(
      pairId: 'p',
      path: 'x.bin',
      size: 42,
      mtimeMs: 7,
      sha256: const Value('hx'),
    ));
    final list = await ManifestStore(db.syncDao).current('p');
    expect(list.single.path, 'x.bin');
    expect(list.single.sha256, 'hx');
    await db.close();
  });
}
