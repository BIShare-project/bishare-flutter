// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_tables.dart';

// ignore_for_file: type=lint
mixin _$SyncDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncPairsTable get syncPairs => attachedDatabase.syncPairs;
  $SyncEntriesTable get syncEntries => attachedDatabase.syncEntries;
  $SyncTombstonesTable get syncTombstones => attachedDatabase.syncTombstones;
  $SyncConflictsTable get syncConflicts => attachedDatabase.syncConflicts;
  $SyncPeerStateTable get syncPeerState => attachedDatabase.syncPeerState;
  $ExpectedChangesTable get expectedChanges => attachedDatabase.expectedChanges;
  $SyncCloudBlobsTable get syncCloudBlobs => attachedDatabase.syncCloudBlobs;
  SyncDaoManager get managers => SyncDaoManager(this);
}

class SyncDaoManager {
  final _$SyncDaoMixin _db;
  SyncDaoManager(this._db);
  $$SyncPairsTableTableManager get syncPairs =>
      $$SyncPairsTableTableManager(_db.attachedDatabase, _db.syncPairs);
  $$SyncEntriesTableTableManager get syncEntries =>
      $$SyncEntriesTableTableManager(_db.attachedDatabase, _db.syncEntries);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(
        _db.attachedDatabase,
        _db.syncTombstones,
      );
  $$SyncConflictsTableTableManager get syncConflicts =>
      $$SyncConflictsTableTableManager(_db.attachedDatabase, _db.syncConflicts);
  $$SyncPeerStateTableTableManager get syncPeerState =>
      $$SyncPeerStateTableTableManager(_db.attachedDatabase, _db.syncPeerState);
  $$ExpectedChangesTableTableManager get expectedChanges =>
      $$ExpectedChangesTableTableManager(
        _db.attachedDatabase,
        _db.expectedChanges,
      );
  $$SyncCloudBlobsTableTableManager get syncCloudBlobs =>
      $$SyncCloudBlobsTableTableManager(
        _db.attachedDatabase,
        _db.syncCloudBlobs,
      );
}
