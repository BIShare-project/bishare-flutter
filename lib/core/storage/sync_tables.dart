import 'package:drift/drift.dart';

import 'app_database.dart';

part 'sync_tables.g.dart';

/// Folder-sync schema (Tahap 4 §4.1), added in drift schemaVersion 4. All tables
/// are keyed by `pairId` so a pair is self-contained and cheaply purged. Secrets
/// never live here: the per-pair AES key (`pairKey`, §7.1) is in
/// `flutter_secure_storage`, not drift — these tables only hold the manifest
/// state, cursors, and content→blob bookkeeping.

/// One configured sync relationship: a local folder ↔ one peer device. v1 is
/// two-way between the user's OWN devices (§G2).
class SyncPairs extends Table {
  /// UUID (not autoincrement) — stable across DB resets and referenced by every
  /// other sync table + the cloud manifest.
  TextColumn get id => text()();
  TextColumn get rootPath => text()();
  TextColumn get peerFingerprint => text()();

  /// 'twoWay' (v1) | 'pushOnly' | 'pullOnly' — enum ready, only twoWay in v1.
  TextColumn get direction => text().withDefault(const Constant('twoWay'))();

  /// 'lanOnly' | 'lanCloud'. lanOnly NEVER touches api.bishare.app for content
  /// (positioning claim). lanCloud enables the Pro-gated store-and-forward (M3).
  TextColumn get mode => text().withDefault(const Constant('lanOnly'))();
  BoolColumn get paused => boolean().withDefault(const Constant(false))();

  /// JSON array of included subtree path prefixes (§8.2); null = whole root.
  TextColumn get selectiveRoots => text().nullable()();

  /// Cloud-blob encryption scheme (§7.1). Forward-compat field so a future
  /// scheme migrates cleanly; v1 is always 'aesgcm-x25519'.
  TextColumn get encryption =>
      text().withDefault(const Constant('aesgcm-x25519'))();

  /// Backend `folder_id` holding this pair's content-addressed store (M3).
  TextColumn get cloudFolderId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The materialized local manifest — one row per path currently on disk under a
/// pair. This is the `local_json` fed to `manifest_diff`. `sha256` is the
/// PLAINTEXT hash (canonical for diff/rename-detection on both transports).
class SyncEntries extends Table {
  TextColumn get pairId => text()();
  TextColumn get path => text()();
  IntColumn get size => integer()();
  IntColumn get mtimeMs => integer()();
  TextColumn get sha256 => text().nullable()(); // null for dirs / unstable
  BoolColumn get isDir => boolean().withDefault(const Constant(false))();

  /// Fingerprint of the device that last authored this entry — feeds
  /// loop-prevention (`originFp`, §4.4).
  TextColumn get originFp => text().nullable()();

  /// Monotonic u64 op cursor (per pair per device) this entry was written at.
  IntColumn get opCursor => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {pairId, path};
}

/// A propagated delete, retained so a stale peer that reappears can't resurrect
/// the file (§6.3). TTL 90 days, swept by the engine.
class SyncTombstones extends Table {
  TextColumn get pairId => text()();
  TextColumn get path => text()();
  IntColumn get deletedAtMs => integer()();
  TextColumn get originFp => text().nullable()();

  @override
  Set<Column> get primaryKey => {pairId, path};
}

/// A recorded conflict: the loser was preserved as a sibling copy (§6.1), never
/// discarded. Surfaced as a badge + resolution sheet.
class SyncConflicts extends Table {
  TextColumn get id => text()(); // uuid
  TextColumn get pairId => text()();
  TextColumn get path => text()();
  TextColumn get loserCopyPath => text()();
  TextColumn get winnerFp => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-pair sync cursors + last-seen markers for each transport. One row per
/// pair (created alongside the pair).
class SyncPeerState extends Table {
  TextColumn get pairId => text()();

  /// This device's monotonic op cursor (bumped on every local change applied).
  IntColumn get ownCursor => integer().withDefault(const Constant(0))();

  /// Highest peer cursor we've fully reconciled (LAN delta handshake, §4.4).
  IntColumn get peerCursor => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastLanSyncAt => dateTime().nullable()();
  DateTimeColumn get lastCloudPushAt => dateTime().nullable()();

  /// Last observed cloud beacon `(last_sync_at,total_files,total_size)` triple
  /// (§5.2) — a change means "pull the manifest". Serialized string.
  TextColumn get cloudFingerprint => text().nullable()();

  @override
  Set<Column> get primaryKey => {pairId};
}

/// Echo suppression (§4.4): every write the engine itself makes is recorded
/// here first; a watcher event that matches (path + expected hash) is dropped
/// so a synced-in change is never re-sent to the peer that sent it. TTL 60s.
class ExpectedChanges extends Table {
  TextColumn get pairId => text()();
  TextColumn get path => text()();
  TextColumn get expectedSha256 => text()();
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {pairId, path};
}

/// (Q2=YA §7.1) Local ledger mapping plaintext content → the ciphertext blob it
/// was uploaded as. Makes cloud push idempotent (re-check `check-exists` on the
/// SAME ciphertext hash) and lets GC know which backend files a manifest still
/// references. Populated on the cloud path only (M3).
class SyncCloudBlobs extends Table {
  TextColumn get pairId => text()();
  TextColumn get plaintextSha256 => text()();
  TextColumn get cloudBlobSha256 => text()(); // ciphertext hash = blob name
  TextColumn get fileId => text()(); // backend file id (for download/delete)
  IntColumn get sizeCipher => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {pairId, plaintextSha256};
}

/// Data access for the folder-sync tables. Kept off [AppDatabase] itself so the
/// sync feature's queries live with its schema. Higher-level orchestration
/// (state machine, reconciliation) sits above this in `features/folder_sync`.
@DriftAccessor(
  tables: [
    SyncPairs,
    SyncEntries,
    SyncTombstones,
    SyncConflicts,
    SyncPeerState,
    ExpectedChanges,
    SyncCloudBlobs,
  ],
)
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  // ---- pairs ----
  Future<List<SyncPair>> allPairs() => select(syncPairs).get();
  Stream<List<SyncPair>> watchPairs() => select(syncPairs).watch();
  Future<SyncPair?> pairById(String id) =>
      (select(syncPairs)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Create a pair and its (zeroed) peer-state row in one transaction so a pair
  /// never exists without cursors.
  Future<void> createPair(SyncPairsCompanion pair, String pairId) =>
      transaction(() async {
        await into(syncPairs).insert(pair);
        await into(
          syncPeerState,
        ).insert(SyncPeerStateCompanion.insert(pairId: pairId));
      });

  Future<void> updatePair(SyncPairsCompanion pair) =>
      update(syncPairs).replace(pair);

  Future<void> setPaused(String id, bool paused) =>
      (update(syncPairs)..where((p) => p.id.equals(id)))
          .write(SyncPairsCompanion(paused: Value(paused)));

  /// Remove a pair and every dependent row (no FK cascade in SQLite here).
  Future<void> deletePair(String id) => transaction(() async {
    for (final go in [
      (delete(syncEntries)..where((t) => t.pairId.equals(id))).go,
      (delete(syncTombstones)..where((t) => t.pairId.equals(id))).go,
      (delete(syncConflicts)..where((t) => t.pairId.equals(id))).go,
      (delete(expectedChanges)..where((t) => t.pairId.equals(id))).go,
      (delete(syncCloudBlobs)..where((t) => t.pairId.equals(id))).go,
      (delete(syncPeerState)..where((t) => t.pairId.equals(id))).go,
      (delete(syncPairs)..where((t) => t.id.equals(id))).go,
    ]) {
      await go();
    }
  });

  // ---- entries (materialized manifest) ----
  Future<List<SyncEntry>> entriesFor(String pairId) =>
      (select(syncEntries)..where((e) => e.pairId.equals(pairId))).get();

  Future<void> upsertEntry(SyncEntriesCompanion row) =>
      into(syncEntries).insertOnConflictUpdate(row);

  Future<void> upsertEntries(List<SyncEntriesCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(syncEntries, rows));

  Future<void> deleteEntry(String pairId, String path) =>
      (delete(syncEntries)
            ..where((e) => e.pairId.equals(pairId) & e.path.equals(path)))
          .go();

  // ---- tombstones ----
  Future<List<SyncTombstone>> tombstonesFor(String pairId) =>
      (select(syncTombstones)..where((t) => t.pairId.equals(pairId))).get();

  Future<void> putTombstone(SyncTombstonesCompanion row) =>
      into(syncTombstones).insertOnConflictUpdate(row);

  Future<void> clearTombstone(String pairId, String path) =>
      (delete(syncTombstones)
            ..where((t) => t.pairId.equals(pairId) & t.path.equals(path)))
          .go();

  /// Drop tombstones older than [ttl] (default 90 days, §6.3).
  Future<void> sweepTombstones(String pairId, {Duration ttl = const Duration(days: 90)}) {
    final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    return (delete(syncTombstones)
          ..where((t) => t.pairId.equals(pairId) & t.deletedAtMs.isSmallerThanValue(cutoff)))
        .go();
  }

  // ---- peer state / cursors ----
  Future<SyncPeerStateData?> peerState(String pairId) =>
      (select(syncPeerState)..where((s) => s.pairId.equals(pairId)))
          .getSingleOrNull();

  Future<void> putPeerState(SyncPeerStateCompanion row) =>
      into(syncPeerState).insertOnConflictUpdate(row);

  /// Reserve and return the next monotonic op cursor for this device.
  Future<int> nextCursor(String pairId) => transaction(() async {
    final s = await peerState(pairId);
    final next = (s?.ownCursor ?? 0) + 1;
    await (update(syncPeerState)..where((p) => p.pairId.equals(pairId)))
        .write(SyncPeerStateCompanion(ownCursor: Value(next)));
    return next;
  });

  // ---- echo suppression ----
  Future<void> expectChange(SyncExpectedChangesRow row) =>
      into(expectedChanges).insertOnConflictUpdate(row.toCompanion());

  /// Consume an expected change matching (path, hash); true if it was ours (so
  /// the watcher event should be dropped). Also GCs expired rows opportunistically.
  Future<bool> consumeExpected(String pairId, String path, String sha256) async {
    final now = DateTime.now();
    await (delete(expectedChanges)..where((e) => e.expiresAt.isSmallerThanValue(now))).go();
    final hit = await (select(expectedChanges)
          ..where((e) =>
              e.pairId.equals(pairId) &
              e.path.equals(path) &
              e.expectedSha256.equals(sha256)))
        .getSingleOrNull();
    if (hit == null) return false;
    await (delete(expectedChanges)
          ..where((e) => e.pairId.equals(pairId) & e.path.equals(path)))
        .go();
    return true;
  }

  // ---- conflicts ----
  Stream<List<SyncConflict>> watchUnresolvedConflicts(String pairId) =>
      (select(syncConflicts)
            ..where((c) => c.pairId.equals(pairId) & c.resolvedAt.isNull()))
          .watch();

  Future<void> recordConflict(SyncConflictsCompanion row) =>
      into(syncConflicts).insert(row);

  Future<void> resolveConflict(String id) =>
      (update(syncConflicts)..where((c) => c.id.equals(id)))
          .write(SyncConflictsCompanion(resolvedAt: Value(DateTime.now())));

  // ---- cloud blob ledger (M3) ----
  Future<SyncCloudBlob?> blobForContent(String pairId, String plaintextSha256) =>
      (select(syncCloudBlobs)
            ..where((b) =>
                b.pairId.equals(pairId) & b.plaintextSha256.equals(plaintextSha256)))
          .getSingleOrNull();

  Future<void> putBlob(SyncCloudBlobsCompanion row) =>
      into(syncCloudBlobs).insertOnConflictUpdate(row);

  Future<List<SyncCloudBlob>> blobsFor(String pairId) =>
      (select(syncCloudBlobs)..where((b) => b.pairId.equals(pairId))).get();
}

/// A small typed helper for [SyncDao.expectChange] so callers don't hand-build a
/// companion with an explicit `expiresAt`.
class SyncExpectedChangesRow {
  const SyncExpectedChangesRow({
    required this.pairId,
    required this.path,
    required this.expectedSha256,
    this.ttl = const Duration(seconds: 60),
  });

  final String pairId;
  final String path;
  final String expectedSha256;
  final Duration ttl;

  ExpectedChangesCompanion toCompanion() => ExpectedChangesCompanion.insert(
    pairId: pairId,
    path: path,
    expectedSha256: expectedSha256,
    expiresAt: DateTime.now().add(ttl),
  );
}
