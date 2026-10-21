import 'dart:io';

import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/storage/sync_tables.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transfer records: newest-first + received-only filter', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.insertRecord(TransferRecordsCompanion.insert(
      fileName: 'a.jpg',
      fileSize: 10,
      direction: 'received',
      deviceAlias: 'x',
      timestamp: DateTime(2026, 1, 1),
    ));
    await db.insertRecord(TransferRecordsCompanion.insert(
      fileName: 'b.mp4',
      fileSize: 20,
      direction: 'sent',
      deviceAlias: 'y',
      timestamp: DateTime(2026, 1, 2),
    ));
    await db.insertRecord(TransferRecordsCompanion.insert(
      fileName: 'c.pdf',
      fileSize: 30,
      direction: 'received',
      deviceAlias: 'z',
      timestamp: DateTime(2026, 1, 3),
    ));

    final all = await db.watchAll().first;
    expect(all.map((r) => r.fileName), ['c.pdf', 'b.mp4', 'a.jpg']); // newest first

    final received = await db.watchReceived().first;
    expect(received.map((r) => r.fileName), ['c.pdf', 'a.jpg']); // 'sent' excluded

    await db.close();
  });

  test('favorites: upsert (no dup) + remove', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.upsertFavorite(FavoriteDevicesCompanion.insert(
      fingerprint: 'fp1',
      addedAt: DateTime(2026, 1, 1),
      customName: const Value('Phone'),
    ));
    expect((await db.watchFavorites().first).single.customName, 'Phone');

    await db.upsertFavorite(FavoriteDevicesCompanion.insert(
      fingerprint: 'fp1',
      addedAt: DateTime(2026, 1, 2),
      autoAccept: const Value(true),
    ));
    final favs = await db.watchFavorites().first;
    expect(favs.length, 1); // upsert by primary key, not a duplicate
    expect(favs.single.autoAccept, true);

    await db.removeFavorite('fp1');
    expect((await db.watchFavorites().first), isEmpty);

    await db.close();
  });

  test('known devices: upsert (no dup, keeps absent columns) + purge + delete',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.upsertKnownDevice(KnownDevicesCompanion.insert(
      fingerprint: 'fp1',
      alias: 'Old Phone',
      lastSeen: DateTime.now().subtract(const Duration(days: 120)),
    ));
    await db.upsertKnownDevice(KnownDevicesCompanion.insert(
      fingerprint: 'fp2',
      alias: 'Laptop',
      lastSeen: DateTime.now(),
      lastIp: const Value('192.168.1.7'),
    ));

    // Re-sighting upserts by primary key: alias refreshes, absent columns
    // (here lastIp) are left untouched, and no duplicate row appears.
    await db.upsertKnownDevice(KnownDevicesCompanion.insert(
      fingerprint: 'fp2',
      alias: 'Laptop Renamed',
      lastSeen: DateTime.now(),
    ));
    var rows = await db.watchKnownDevices().first;
    expect(rows.length, 2);
    final fp2 = rows.firstWhere((r) => r.fingerprint == 'fp2');
    expect(fp2.alias, 'Laptop Renamed');
    expect(fp2.lastIp, '192.168.1.7');

    await db.purgeOlderThan(90); // fp1 was last seen 120 days ago
    rows = await db.watchKnownDevices().first;
    expect(rows.map((r) => r.fingerprint), ['fp2']);

    await db.deleteKnownDevice('fp2');
    expect(await db.watchKnownDevices().first, isEmpty);

    await db.close();
  });

  test('purge never drops a starred device, however long unseen', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final long = DateTime.now().subtract(const Duration(days: 200));

    // Two equally stale roster entries; only one of them is starred.
    await db.upsertKnownDevice(KnownDevicesCompanion.insert(
      fingerprint: 'starred',
      alias: 'Trusted Mac',
      lastSeen: long,
    ));
    await db.upsertKnownDevice(KnownDevicesCompanion.insert(
      fingerprint: 'stale',
      alias: 'Forgotten Phone',
      lastSeen: long,
    ));
    await db.upsertFavorite(FavoriteDevicesCompanion.insert(
      fingerprint: 'starred',
      addedAt: DateTime(2026, 1, 1),
    ));

    await db.purgeOlderThan(90);

    // The favorite survives despite being 200 days stale; the unstarred peer is
    // dropped.
    final rows = await db.watchKnownDevices().first;
    expect(rows.map((r) => r.fingerprint), ['starred']);

    await db.close();
  });

  test('migration v2→v3: creates clipboardHistory, keeps v2 data', () async {
    final dir = await Directory.systemTemp.createTemp('bishare_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    // Seed a real v2 database (the Wave 0 schema: three tables, knownDevices
    // added by the v1→v2 block) before drift opens it, so AppDatabase runs
    // onUpgrade(2 → 3) instead of onCreate.
    final db = AppDatabase(NativeDatabase(file, setup: (raw) {
      if (raw.userVersion != 0) return; // only seed the very first open
      raw.execute('''
        CREATE TABLE transfer_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_name TEXT NOT NULL,
          saved_path TEXT NULL,
          file_size INTEGER NOT NULL,
          file_type TEXT NULL,
          direction TEXT NOT NULL,
          device_alias TEXT NOT NULL,
          device_fingerprint TEXT NULL,
          encrypted INTEGER NOT NULL DEFAULT 0,
          verified INTEGER NOT NULL DEFAULT 1,
          timestamp INTEGER NOT NULL
        );
      ''');
      raw.execute('''
        CREATE TABLE favorite_devices (
          fingerprint TEXT NOT NULL,
          custom_name TEXT NULL,
          auto_accept INTEGER NOT NULL DEFAULT 0,
          added_at INTEGER NOT NULL,
          PRIMARY KEY (fingerprint)
        );
      ''');
      raw.execute('''
        CREATE TABLE known_devices (
          fingerprint TEXT NOT NULL,
          alias TEXT NOT NULL,
          device_model TEXT NULL,
          device_type TEXT NULL,
          last_seen INTEGER NOT NULL,
          last_ip TEXT NULL,
          capabilities TEXT NULL,
          workspace_id TEXT NULL,
          PRIMARY KEY (fingerprint)
        );
      ''');
      raw.execute(
        'INSERT INTO transfer_records (file_name, file_size, direction, device_alias, timestamp) '
        "VALUES ('old.jpg', 5, 'received', 'x', 0);",
      );
      raw.execute(
        'INSERT INTO known_devices (fingerprint, alias, last_seen) '
        "VALUES ('fp1', 'Phone', 0);",
      );
      raw.userVersion = 2;
    }));

    // v2 rows survive the upgrade...
    final all = await db.watchAll().first;
    expect(all.single.fileName, 'old.jpg');
    expect((await db.watchKnownDevices().first).single.alias, 'Phone');

    // ...and the new clipboard table exists and is usable.
    await db.insertClipboardEntry(ClipboardHistoryCompanion.insert(
      kind: 'text',
      textContent: const Value('hello'),
      senderAlias: 'Mac',
      createdAt: DateTime(2026, 1, 1),
    ));
    final entries = await db.watchClipboard(20).first;
    expect(entries.single.textContent, 'hello');

    await db.close();
  });

  test('sync (v4 fresh): pair lifecycle, entries, echo-suppression, cursor',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dao = db.syncDao;

    // createPair also seeds the peer-state row in one transaction.
    await dao.createPair(
      SyncPairsCompanion.insert(
        id: 'pair1',
        rootPath: '/Users/me/Docs',
        peerFingerprint: 'peerFP',
        createdAt: DateTime(2026, 1, 1),
        mode: const Value('lanCloud'),
      ),
      'pair1',
    );
    final pair = await dao.pairById('pair1');
    expect(pair!.mode, 'lanCloud');
    expect(pair.encryption, 'aesgcm-x25519'); // §7.1 default
    expect((await dao.peerState('pair1'))!.ownCursor, 0);

    // Materialized manifest: batch upsert, then read back.
    await dao.upsertEntries([
      SyncEntriesCompanion.insert(
        pairId: 'pair1',
        path: 'a.txt',
        size: 5,
        mtimeMs: 1000,
        sha256: const Value('abc'),
      ),
      SyncEntriesCompanion.insert(
        pairId: 'pair1',
        path: 'sub',
        size: 0,
        mtimeMs: 900,
        isDir: const Value(true),
      ),
    ]);
    expect((await dao.entriesFor('pair1')).length, 2);

    // Cursor is monotonic and persisted.
    expect(await dao.nextCursor('pair1'), 1);
    expect(await dao.nextCursor('pair1'), 2);
    expect((await dao.peerState('pair1'))!.ownCursor, 2);

    // Echo-suppression: an expected write is consumed once (dropped), then gone.
    await dao.expectChange(const SyncExpectedChangesRow(
      pairId: 'pair1',
      path: 'a.txt',
      expectedSha256: 'abc',
    ));
    expect(await dao.consumeExpected('pair1', 'a.txt', 'abc'), isTrue);
    expect(await dao.consumeExpected('pair1', 'a.txt', 'abc'), isFalse);
    // A non-matching hash is never suppressed (a genuine local edit).
    expect(await dao.consumeExpected('pair1', 'a.txt', 'zzz'), isFalse);

    // Tombstone sweep keeps fresh, drops aged.
    final now = DateTime.now().millisecondsSinceEpoch;
    await dao.putTombstone(SyncTombstonesCompanion.insert(
      pairId: 'pair1',
      path: 'old.txt',
      deletedAtMs: now - const Duration(days: 100).inMilliseconds,
    ));
    await dao.putTombstone(SyncTombstonesCompanion.insert(
      pairId: 'pair1',
      path: 'recent.txt',
      deletedAtMs: now,
    ));
    await dao.sweepTombstones('pair1');
    expect((await dao.tombstonesFor('pair1')).map((t) => t.path), ['recent.txt']);

    // Cloud blob ledger (M3) round-trips by content hash.
    await dao.putBlob(SyncCloudBlobsCompanion.insert(
      pairId: 'pair1',
      plaintextSha256: 'abc',
      cloudBlobSha256: 'cipherhash',
      fileId: 'file_1',
    ));
    expect((await dao.blobForContent('pair1', 'abc'))!.fileId, 'file_1');

    // deletePair cascades every dependent row.
    await dao.deletePair('pair1');
    expect(await dao.pairById('pair1'), isNull);
    expect(await dao.entriesFor('pair1'), isEmpty);
    expect(await dao.peerState('pair1'), isNull);
    expect(await dao.blobsFor('pair1'), isEmpty);

    await db.close();
  });

  test('migration v3→v4: creates sync tables, keeps v3 data', () async {
    final dir = await Directory.systemTemp.createTemp('bishare_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    // Seed a real v3 database (four tables) at userVersion 3 so AppDatabase runs
    // onUpgrade(3 → 4) instead of onCreate.
    final db = AppDatabase(NativeDatabase(file, setup: (raw) {
      if (raw.userVersion != 0) return;
      raw.execute('''
        CREATE TABLE transfer_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT, file_name TEXT NOT NULL,
          saved_path TEXT NULL, file_size INTEGER NOT NULL, file_type TEXT NULL,
          direction TEXT NOT NULL, device_alias TEXT NOT NULL,
          device_fingerprint TEXT NULL, encrypted INTEGER NOT NULL DEFAULT 0,
          verified INTEGER NOT NULL DEFAULT 1, timestamp INTEGER NOT NULL);
      ''');
      raw.execute('''
        CREATE TABLE favorite_devices (fingerprint TEXT NOT NULL,
          custom_name TEXT NULL, auto_accept INTEGER NOT NULL DEFAULT 0,
          added_at INTEGER NOT NULL, PRIMARY KEY (fingerprint));
      ''');
      raw.execute('''
        CREATE TABLE known_devices (fingerprint TEXT NOT NULL, alias TEXT NOT NULL,
          device_model TEXT NULL, device_type TEXT NULL, last_seen INTEGER NOT NULL,
          last_ip TEXT NULL, capabilities TEXT NULL, workspace_id TEXT NULL,
          PRIMARY KEY (fingerprint));
      ''');
      raw.execute('''
        CREATE TABLE clipboard_history (id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL, text TEXT NULL, mime TEXT NULL, file_name TEXT NULL,
          file_path TEXT NULL, preview_path TEXT NULL, sender_alias TEXT NOT NULL,
          sender_fingerprint TEXT NULL, created_at INTEGER NOT NULL);
      ''');
      raw.execute(
        'INSERT INTO transfer_records (file_name, file_size, direction, device_alias, timestamp) '
        "VALUES ('old.jpg', 5, 'received', 'x', 0);",
      );
      raw.userVersion = 3;
    }));

    // v3 rows survive the upgrade...
    expect((await db.watchAll().first).single.fileName, 'old.jpg');

    // ...and the new sync tables exist and are usable.
    await db.syncDao.createPair(
      SyncPairsCompanion.insert(
        id: 'p',
        rootPath: '/x',
        peerFingerprint: 'fp',
        createdAt: DateTime(2026, 1, 1),
      ),
      'p',
    );
    expect((await db.syncDao.allPairs()).single.rootPath, '/x');

    await db.close();
  });

  test('migration v1→v2: creates knownDevices, keeps v1 data', () async {
    final dir = await Directory.systemTemp.createTemp('bishare_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    // Seed a real v1 database (the shipped schema: two tables, no
    // MigrationStrategy) before drift opens it, so AppDatabase runs
    // onUpgrade(1 → 2) instead of onCreate.
    final db = AppDatabase(NativeDatabase(file, setup: (raw) {
      if (raw.userVersion != 0) return; // only seed the very first open
      raw.execute('''
        CREATE TABLE transfer_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_name TEXT NOT NULL,
          saved_path TEXT NULL,
          file_size INTEGER NOT NULL,
          file_type TEXT NULL,
          direction TEXT NOT NULL,
          device_alias TEXT NOT NULL,
          device_fingerprint TEXT NULL,
          encrypted INTEGER NOT NULL DEFAULT 0,
          verified INTEGER NOT NULL DEFAULT 1,
          timestamp INTEGER NOT NULL
        );
      ''');
      raw.execute('''
        CREATE TABLE favorite_devices (
          fingerprint TEXT NOT NULL,
          custom_name TEXT NULL,
          auto_accept INTEGER NOT NULL DEFAULT 0,
          added_at INTEGER NOT NULL,
          PRIMARY KEY (fingerprint)
        );
      ''');
      raw.execute(
        'INSERT INTO transfer_records (file_name, file_size, direction, device_alias, timestamp) '
        "VALUES ('old.jpg', 5, 'received', 'x', 0);",
      );
      raw.userVersion = 1;
    }));

    // v1 rows survive the upgrade...
    final all = await db.watchAll().first;
    expect(all.single.fileName, 'old.jpg');

    // ...and the new table exists and is usable.
    await db.upsertKnownDevice(KnownDevicesCompanion.insert(
      fingerprint: 'fp1',
      alias: 'Phone',
      lastSeen: DateTime(2026, 1, 1),
    ));
    expect((await db.watchKnownDevices().first).single.alias, 'Phone');

    await db.close();
  });

  test('migration v4→v5: creates the Drive tables, keeps v4 data', () async {
    final dir = await Directory.systemTemp.createTemp('bishare_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    // A real database at the current schema, then turned back into v4 by
    // dropping the four Drive tables, so AppDatabase runs onUpgrade(4 → 5)
    // on a database that has every v4 table exactly as drift made it.
    final first = AppDatabase(NativeDatabase(file));
    await first.insertRecord(TransferRecordsCompanion.insert(
      fileName: 'old.jpg',
      fileSize: 5,
      direction: 'received',
      deviceAlias: 'x',
      timestamp: DateTime(2026, 1, 1),
    ));
    await first.close();

    final db = AppDatabase(NativeDatabase(file, setup: (raw) {
      if (raw.userVersion != 6) return;
      for (final t in ['vault_objects', 'vault_transfers', 'vault_state', 'vault_backed_up_assets']) {
        raw.execute('DROP TABLE $t;');
      }
      raw.userVersion = 4;
    }));

    // v4 rows survive the upgrade...
    expect((await db.watchAll().first).single.fileName, 'old.jpg');

    // ...and the Drive tables exist and are usable.
    final vault = db.vaultDao;
    await vault.setStateValue('seq', '7');
    expect(await vault.stateValue('seq'), '7');
    await vault.upsertObjects([
      VaultObjectsCompanion.insert(id: 'd', name: 'Photos', kind: 'dir', mtime: 1, seq: 1, createdAt: 1, encMeta: 'x'),
      VaultObjectsCompanion.insert(id: 'f', parent: const Value('d'), name: 'b.jpg', kind: 'file', mtime: 1, seq: 2, createdAt: 1, encMeta: 'y'),
      VaultObjectsCompanion.insert(id: 'a', name: 'a.txt', kind: 'file', mtime: 1, seq: 3, createdAt: 1, encMeta: 'z'),
    ]);
    expect((await vault.watchChildren(null).first).map((o) => o.name), ['Photos', 'a.txt'], reason: 'folders first');
    expect((await vault.watchChildren('d').first).single.name, 'b.jpg');
    await vault.clearAll();
    expect(await vault.watchChildren(null).first, isEmpty);
    expect((await db.watchAll().first).single.fileName, 'old.jpg', reason: 'clearing Drive touches nothing else');

    await db.close();
  });

  test('migration v5→v6: transfers learn their library asset, keep v5 rows', () async {
    final dir = await Directory.systemTemp.createTemp('bishare_db_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/app.db');

    final first = AppDatabase(NativeDatabase(file));
    await first.vaultDao.enqueue(VaultTransfersCompanion.insert(
      direction: 'up',
      objectId: 'o1',
      name: 'IMG_1.jpg',
      localPath: '/x/IMG_1.jpg',
      size: 3,
      state: 'queued',
      createdAt: 1,
      updatedAt: 1,
    ));
    await first.close();

    // Back to v5: the column did not exist then.
    final db = AppDatabase(NativeDatabase(file, setup: (raw) {
      if (raw.userVersion != 6) return;
      raw.execute('ALTER TABLE vault_transfers DROP COLUMN asset_id;');
      raw.userVersion = 5;
    }));

    final old = (await db.vaultDao.pendingTransfers()).single;
    expect(old.name, 'IMG_1.jpg', reason: 'v5 rows survive');
    expect(old.assetId, isNull);
    await db.vaultDao.enqueue(VaultTransfersCompanion.insert(
      direction: 'up',
      objectId: 'o2',
      name: 'IMG_2.jpg',
      localPath: '/x/IMG_2.jpg',
      size: 3,
      state: 'queued',
      createdAt: 2,
      updatedAt: 2,
      assetId: const Value('asset-2'),
    ));
    expect((await db.vaultDao.pendingTransfers()).map((t) => t.assetId), [null, 'asset-2']);
    await db.close();
  });
}
