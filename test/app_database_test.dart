import 'package:bishare/core/storage/app_database.dart';
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
}
