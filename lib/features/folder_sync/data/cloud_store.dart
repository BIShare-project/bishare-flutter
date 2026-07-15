/// The narrow slice of the drive backend folder-sync needs (§5.2) — injectable
/// so the adapter tests run against an in-memory store. Production (M3b) wraps
/// the AuthedDio endpoints the Drive client already exercises. Every byte that
/// crosses this interface is CIPHERTEXT (§7.1): the store never sees content.
library;

import 'dart:typed_data';

/// One stored object (a blob named by its ciphertext hash, or a manifest).
class CloudFileRef {
  const CloudFileRef({required this.id, required this.name, this.size = 0});

  final String id;
  final String name;
  final int size;
}

/// The `sync-status` change beacon: the fingerprint triple that answers "did
/// anything change server-side since I last looked?" plus the account tier
/// (the Pro gate rides the same call).
class CloudSyncBeacon {
  const CloudSyncBeacon({
    required this.fingerprint,
    required this.tier,
  });

  /// `(last_sync_at, total_files, total_size)` serialized — an opaque token;
  /// only equality matters.
  final String fingerprint;
  final String tier;
}

abstract class SyncCloudStore {
  /// The backend folder holding a pair's content-addressed store; created on
  /// first use (hidden from the Drive UI client-side — Q3).
  Future<String> ensureFolder(String name);

  /// Per-account dedup over CIPHERTEXT hashes (1–500 lowercase hex).
  Future<Map<String, bool>> checkExists(List<String> hashes);

  /// Upload one object into [folderId] under [name]; returns its ref.
  Future<CloudFileRef> upload(String folderId, String name, Uint8List bytes);

  Future<List<CloudFileRef>> list(String folderId);

  Future<Uint8List> download(String fileId);

  /// Soft-delete (server trash) — used to retire a replaced manifest + GC.
  Future<void> delete(String fileId);

  Future<CloudSyncBeacon> beacon();
}
