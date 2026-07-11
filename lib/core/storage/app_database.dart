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

/// Every peer this device has ever seen (a discovery sighting). The persistent
/// roster behind the Devices dashboard; live online/away/offline presence is
/// layered on top by `PresenceDeviceRegistry`. `capabilities` and `workspaceId`
/// are reserved for later waves (capability badges, workspace scoping).
class KnownDevices extends Table {
  TextColumn get fingerprint => text()();
  TextColumn get alias => text()();
  TextColumn get deviceModel => text().nullable()();
  TextColumn get deviceType => text().nullable()();
  DateTimeColumn get lastSeen => dateTime()();
  TextColumn get lastIp => text().nullable()();
  TextColumn get capabilities => text().nullable()();
  TextColumn get workspaceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {fingerprint};
}

/// One synced clipboard item (text or image), ring-buffered to the last
/// [BIShareConfig.clipboardHistoryMax] entries by `ClipboardHistoryStore`.
/// Image entries keep their bytes on disk (`filePath`, plus an optional small
/// `previewPath` when only the announce preview was obtained).
class ClipboardHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()(); // 'text' | 'image'
  // Dart getter can't be `text` (collides with drift's Table.text builder);
  // `.named` keeps the SQL column name from the plan.
  TextColumn get textContent => text().named('text').nullable()();
  TextColumn get mime => text().nullable()();
  TextColumn get fileName => text().nullable()();
  TextColumn get filePath => text().nullable()();
  TextColumn get previewPath => text().nullable()();
  TextColumn get senderAlias => text()();
  TextColumn get senderFingerprint => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(
  tables: [TransferRecords, FavoriteDevices, KnownDevices, ClipboardHistory],
)
class AppDatabase extends _$AppDatabase {
  /// Pass a custom [executor] in tests (e.g. `NativeDatabase.memory()`); the app
  /// uses drift_flutter's lazy, background-isolate connection.
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'bishare'));

  @override
  int get schemaVersion => 3;

  /// The ONE incremental upgrade path. Every future schema bump adds its own
  /// `if (from < N)` block below (from < 4, from < 5, …) — never edit or
  /// reorder a shipped block, or upgrades from old installs break.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(knownDevices);
      }
      if (from < 3) {
        await m.createTable(clipboardHistory);
      }
    },
  );

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

  // ---- known devices ----
  Stream<List<KnownDevice>> watchKnownDevices() =>
      (select(knownDevices)
            ..orderBy([(t) => OrderingTerm.desc(t.lastSeen)]))
          .watch();

  Future<void> upsertKnownDevice(KnownDevicesCompanion row) =>
      into(knownDevices).insertOnConflictUpdate(row);

  Future<void> deleteKnownDevice(String fingerprint) => (delete(
    knownDevices,
  )..where((t) => t.fingerprint.equals(fingerprint))).go();

  /// Drops roster entries not seen for [days] days — keeps the Devices list
  /// from accumulating peers that are long gone. Starred (favorite) devices are
  /// never purged: a trusted peer stays on the roster through any absence.
  Future<void> purgeOlderThan(int days) {
    final favoriteFingerprints = selectOnly(favoriteDevices)
      ..addColumns([favoriteDevices.fingerprint]);
    return (delete(knownDevices)..where(
          (t) =>
              t.lastSeen.isSmallerThanValue(
                DateTime.now().subtract(Duration(days: days)),
              ) &
              t.fingerprint.isNotInQuery(favoriteFingerprints),
        ))
        .go();
  }

  // ---- clipboard history (ring buffer — see ClipboardHistoryStore) ----
  Stream<List<ClipboardHistoryData>> watchClipboard(int limit) =>
      (select(clipboardHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(limit))
          .watch();

  Future<int> insertClipboardEntry(ClipboardHistoryCompanion row) =>
      into(clipboardHistory).insert(row);

  /// Rows past the newest [keep] (oldest-first tail) — what the ring buffer
  /// trims after an insert.
  Future<List<ClipboardHistoryData>> clipboardOverflow(int keep) =>
      (select(clipboardHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.id)])
            ..limit(-1, offset: keep))
          .get();

  Future<void> deleteClipboardEntry(int id) =>
      (delete(clipboardHistory)..where((t) => t.id.equals(id))).go();

  Future<List<ClipboardHistoryData>> allClipboardEntries() =>
      select(clipboardHistory).get();

  Future<void> clearClipboardHistory() => delete(clipboardHistory).go();
}
