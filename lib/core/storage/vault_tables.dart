import 'package:drift/drift.dart';

import 'app_database.dart';

part 'vault_tables.g.dart';

/// BIShare Drive's local tables (drive-plan.md "Local database", schema 5).
/// Additive only: nothing here touches a transfer table, and the Drive code
/// is the only reader and writer.

/// The opened index: one row per live object of the vault this device is
/// signed in to. Names and the tree come from `enc_meta`, opened with
/// `K_meta` on this device; the raw sealed string is kept too, because the
/// file key is read from it only when a file is opened or shared.
class VaultObjects extends Table {
  TextColumn get id => text()();
  TextColumn get parent => text().nullable()();
  TextColumn get name => text()();

  /// 'file' or 'dir'.
  TextColumn get kind => text()();

  /// Plaintext size of a file.
  IntColumn get size => integer().nullable()();

  /// Modification time, Unix milliseconds.
  IntColumn get mtime => integer()();
  TextColumn get mime => text().nullable()();

  /// b64u SHA-256 of the plaintext: what photo backup and the uploader
  /// compare against, so the same file is not sent twice.
  TextColumn get hash => text().nullable()();
  TextColumn get blobId => text().nullable()();

  /// Stored (ciphertext) size, what the quota counts.
  IntColumn get blobSize => integer().nullable()();
  BoolColumn get hasThumb => boolean().withDefault(const Constant(false))();
  IntColumn get seq => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get trashedAt => integer().nullable()();
  TextColumn get encMeta => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The upload and download queue. It survives a restart: an upload keeps its
/// object id, its sealed metadata (which carries the file key, sealed) and
/// the parts already sent, so it resumes where it stopped.
class VaultTransfers extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'up' or 'down'.
  TextColumn get direction => text()();
  TextColumn get objectId => text()();
  TextColumn get parent => text().nullable()();
  TextColumn get name => text()();

  /// Upload: the file to send. Download: where the file goes.
  TextColumn get localPath => text()();

  /// Upload: the sealed temporary file, once made.
  TextColumn get sealedPath => text().nullable()();

  /// Plaintext size.
  IntColumn get size => integer()();

  /// 'queued', 'sealing', 'sending', 'finishing', 'receiving', 'done',
  /// 'failed', 'cancelled'.
  TextColumn get state => text()();
  TextColumn get uploadId => text().nullable()();
  TextColumn get encMeta => text().nullable()();

  /// Multipart: JSON list of `{"n": part number, "e": ETag}` already sent.
  TextColumn get partsDone => text().nullable()();
  IntColumn get bytesDone => integer().withDefault(const Constant(0))();
  TextColumn get error => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

/// Small facts about the vault on this device: its id, the last sequence
/// number pulled, plan and quota as last seen.
class VaultState extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Photo backup (phase 5): which library assets went up, so a reinstall or a
/// second phone does not send them again.
class VaultBackedUpAssets extends Table {
  TextColumn get assetId => text()();
  TextColumn get hash => text()();
  TextColumn get objectId => text()();
  IntColumn get at => integer()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Every query the Drive code makes, in one place.
@DriftAccessor(
  tables: [VaultObjects, VaultTransfers, VaultState, VaultBackedUpAssets],
)
class VaultDao extends DatabaseAccessor<AppDatabase> with _$VaultDaoMixin {
  VaultDao(super.db);

  // ---- state ----
  Future<String?> stateValue(String key) async => (await (select(
    vaultState,
  )..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setStateValue(String key, String value) => into(
    vaultState,
  ).insertOnConflictUpdate(VaultStateCompanion.insert(key: key, value: value));

  // ---- the index ----
  Future<void> upsertObjects(List<VaultObjectsCompanion> rows) =>
      batch((b) => b.insertAllOnConflictUpdate(vaultObjects, rows));

  Future<void> deleteObjects(List<String> ids) =>
      (delete(vaultObjects)..where((t) => t.id.isIn(ids))).go();

  Future<VaultObject?> object(String id) =>
      (select(vaultObjects)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The live children of a folder (null = the root): folders first, then by
  /// name.
  Stream<List<VaultObject>> watchChildren(String? parent) =>
      (select(vaultObjects)
            ..where(
              (t) =>
                  (parent == null
                      ? t.parent.isNull()
                      : t.parent.equals(parent)) &
                  t.trashedAt.isNull(),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.kind), // 'dir' sorts before 'file'
              (t) => OrderingTerm.asc(t.name.collate(Collate.noCase)),
            ]))
          .watch();

  /// Live files and folders whose name contains [query] (any case), for
  /// search across the whole Drive.
  Stream<List<VaultObject>> watchSearch(String query, {int limit = 300}) {
    final q = query.trim();
    final escaped = q
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    return (select(vaultObjects)
          ..where(
            (t) =>
                t.trashedAt.isNull() &
                t.name
                    .collate(Collate.noCase)
                    .like('%$escaped%', escapeChar: '\\'),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.name.collate(Collate.noCase)),
          ])
          ..limit(limit))
        .watch();
  }

  /// Live files added most recently, newest first.
  Stream<List<VaultObject>> watchRecent({int limit = 200}) =>
      (select(vaultObjects)
            ..where((t) => t.kind.equals('file') & t.trashedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit))
          .watch();

  /// Live files whose MIME type starts with one of [prefixes] or equals one of
  /// [types], newest first.
  Stream<List<VaultObject>> watchFilesOfType({
    List<String> prefixes = const [],
    List<String> types = const [],
  }) =>
      (select(vaultObjects)
            ..where((t) {
              Expression<bool> match = const Constant(false);
              for (final p in prefixes) {
                match = match | t.mime.like('$p%');
              }
              if (types.isNotEmpty) match = match | t.mime.isIn(types);
              return t.kind.equals('file') & t.trashedAt.isNull() & match;
            })
            ..orderBy([(t) => OrderingTerm.desc(t.mtime)]))
          .watch();

  /// Every live object, for the storage breakdown.
  Stream<List<VaultObject>> watchLive() =>
      (select(vaultObjects)..where((t) => t.trashedAt.isNull())).watch();

  /// How many live things each folder holds (key null: the top of the Drive).
  Stream<Map<String?, int>> watchChildCounts() {
    final count = vaultObjects.id.count();
    final q = selectOnly(vaultObjects)
      ..addColumns([vaultObjects.parent, count])
      ..where(vaultObjects.trashedAt.isNull())
      ..groupBy([vaultObjects.parent]);
    return q.watch().map(
      (rows) => {
        for (final r in rows) r.read(vaultObjects.parent): r.read(count) ?? 0,
      },
    );
  }

  /// How many objects point at [blobId] (the same content stored once).
  Future<int> countWithBlob(String blobId) async {
    final count = vaultObjects.id.count();
    final row =
        await (selectOnly(vaultObjects)
              ..addColumns([count])
              ..where(vaultObjects.blobId.equals(blobId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// The folders from the top of the Drive down to [id] (included).
  Future<List<VaultObject>> pathTo(String id) async {
    final out = <VaultObject>[];
    final seen = <String>{};
    String? at = id;
    while (at != null && seen.add(at)) {
      final o = await object(at);
      if (o == null) break;
      out.insert(0, o);
      at = o.parent;
    }
    return out;
  }

  /// Every live folder, for the "Move to" picker.
  Future<List<VaultObject>> liveFolders() =>
      (select(vaultObjects)
            ..where((t) => t.kind.equals('dir') & t.trashedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.name.collate(Collate.noCase)),
            ]))
          .get();

  /// The live children of a folder (null = the root), once.
  Future<List<VaultObject>> liveChildren(String? parent) =>
      (select(vaultObjects)..where(
            (t) =>
                (parent == null ? t.parent.isNull() : t.parent.equals(parent)) &
                t.trashedAt.isNull(),
          ))
          .get();

  /// Every child of a folder, trashed ones too.
  Future<List<VaultObject>> childrenOf(String parent) =>
      (select(vaultObjects)..where((t) => t.parent.equals(parent))).get();

  Stream<List<VaultObject>> watchTrash() =>
      (select(vaultObjects)
            ..where((t) => t.trashedAt.isNotNull())
            ..orderBy([(t) => OrderingTerm.desc(t.trashedAt)]))
          .watch();

  /// A live file with this plaintext hash, if any: the uploader then links to
  /// it instead of sending the bytes again.
  Future<VaultObject?> fileWithHash(String hash) =>
      (select(vaultObjects)
            ..where(
              (t) =>
                  t.hash.equals(hash) &
                  t.kind.equals('file') &
                  t.blobId.isNotNull(),
            )
            ..limit(1))
          .getSingleOrNull();

  /// Any object (trashed ones too) whose content is the blob [blobId]: the
  /// file key of a blob the server says this vault already holds.
  Future<VaultObject?> fileWithBlob(String blobId) =>
      (select(vaultObjects)
            ..where((t) => t.blobId.equals(blobId))
            ..limit(1))
          .getSingleOrNull();

  // ---- the queue ----
  Future<int> enqueue(VaultTransfersCompanion row) =>
      into(vaultTransfers).insert(row);

  Future<void> updateTransfer(int id, VaultTransfersCompanion patch) =>
      (update(vaultTransfers)..where((t) => t.id.equals(id))).write(patch);

  Future<VaultTransfer?> transfer(int id) =>
      (select(vaultTransfers)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// What still has work to do, oldest first.
  Future<List<VaultTransfer>> pendingTransfers() =>
      (select(vaultTransfers)
            ..where((t) => t.state.isNotIn(['done', 'failed', 'cancelled']))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();

  Stream<List<VaultTransfer>> watchTransfers() => (select(
    vaultTransfers,
  )..orderBy([(t) => OrderingTerm.desc(t.id)])).watch();

  Future<void> clearFinishedTransfers() => (delete(
    vaultTransfers,
  )..where((t) => t.state.isIn(['done', 'cancelled']))).go();

  // ---- photo backup ----
  Future<bool> assetBackedUp(String assetId) async =>
      (await (select(
        vaultBackedUpAssets,
      )..where((t) => t.assetId.equals(assetId))).getSingleOrNull()) !=
      null;

  Future<void> markAssetBackedUp(
    String assetId,
    String hash,
    String objectId,
  ) => into(vaultBackedUpAssets).insertOnConflictUpdate(
    VaultBackedUpAssetsCompanion.insert(
      assetId: assetId,
      hash: hash,
      objectId: objectId,
      at: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  /// Sign-out, another account, or a resync: everything Drive on this device
  /// goes, in one transaction.
  Future<void> clearAll() => transaction(() async {
    await delete(vaultObjects).go();
    await delete(vaultTransfers).go();
    await delete(vaultState).go();
    await delete(vaultBackedUpAssets).go();
  });

  /// Only the index (a resync from sequence 0); the queue stays.
  Future<void> clearIndex() => delete(vaultObjects).go();
}
