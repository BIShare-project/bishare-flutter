import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// One row per completed file transfer (sent or received). The Inbox is simply a
/// query over `direction == 'received'`; History is the full table. Replaces the
/// native SwiftData `TransferRecord`.
class TransferRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fileName => text()();
  TextColumn get savedPath => text().nullable()(); // set for received files
  IntColumn get fileSize => integer()();
  TextColumn get fileType => text().nullable()();
  TextColumn get direction => text()(); // 'sent' | 'received'
  TextColumn get deviceAlias => text()();
  TextColumn get deviceFingerprint => text().nullable()();
  BoolColumn get encrypted => boolean().withDefault(const Constant(false))();
  BoolColumn get verified => boolean().withDefault(const Constant(true))();
  DateTimeColumn get timestamp => dateTime()();
}

/// A trusted peer (star + optional custom name + per-device auto-accept).
class FavoriteDevices extends Table {
  TextColumn get fingerprint => text()();
  TextColumn get customName => text().nullable()();
  BoolColumn get autoAccept => boolean().withDefault(const Constant(false))();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {fingerprint};
}

@DriftDatabase(tables: [TransferRecords, FavoriteDevices])
class AppDatabase extends _$AppDatabase {
  /// Pass a custom [executor] in tests (e.g. `NativeDatabase.memory()`); the app
  /// uses drift_flutter's lazy, background-isolate connection.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'bishare'));

  @override
  int get schemaVersion => 1;

  // ---- transfer history ----
  Stream<List<TransferRecord>> watchReceived() =>
      (select(transferRecords)
            ..where((t) => t.direction.equals('received'))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(500))
          .watch();

  Stream<List<TransferRecord>> watchAll() =>
      (select(transferRecords)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(1000))
          .watch();

  /// One-shot received list (newest first) — used by the browser file list.
  Future<List<TransferRecord>> receivedRecords() =>
      (select(transferRecords)
            ..where((t) => t.direction.equals('received'))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(500))
          .get();

  Future<int> insertRecord(TransferRecordsCompanion row) =>
      into(transferRecords).insert(row);

  Future<void> deleteRecord(int id) =>
      (delete(transferRecords)..where((t) => t.id.equals(id))).go();

  Future<void> clearHistory() => delete(transferRecords).go();

  // ---- favorites ----
  Stream<List<FavoriteDevice>> watchFavorites() =>
      select(favoriteDevices).watch();

  Future<void> upsertFavorite(FavoriteDevicesCompanion row) =>
      into(favoriteDevices).insertOnConflictUpdate(row);

  Future<void> removeFavorite(String fingerprint) => (delete(
    favoriteDevices,
  )..where((t) => t.fingerprint.equals(fingerprint))).go();
}
