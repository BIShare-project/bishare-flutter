// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_tables.dart';

// ignore_for_file: type=lint
mixin _$VaultDaoMixin on DatabaseAccessor<AppDatabase> {
  $VaultObjectsTable get vaultObjects => attachedDatabase.vaultObjects;
  $VaultTransfersTable get vaultTransfers => attachedDatabase.vaultTransfers;
  $VaultStateTable get vaultState => attachedDatabase.vaultState;
  $VaultBackedUpAssetsTable get vaultBackedUpAssets =>
      attachedDatabase.vaultBackedUpAssets;
  VaultDaoManager get managers => VaultDaoManager(this);
}

class VaultDaoManager {
  final _$VaultDaoMixin _db;
  VaultDaoManager(this._db);
  $$VaultObjectsTableTableManager get vaultObjects =>
      $$VaultObjectsTableTableManager(_db.attachedDatabase, _db.vaultObjects);
  $$VaultTransfersTableTableManager get vaultTransfers =>
      $$VaultTransfersTableTableManager(
        _db.attachedDatabase,
        _db.vaultTransfers,
      );
  $$VaultStateTableTableManager get vaultState =>
      $$VaultStateTableTableManager(_db.attachedDatabase, _db.vaultState);
  $$VaultBackedUpAssetsTableTableManager get vaultBackedUpAssets =>
      $$VaultBackedUpAssetsTableTableManager(
        _db.attachedDatabase,
        _db.vaultBackedUpAssets,
      );
}
