import 'dart:typed_data';

import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_api.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';
import 'vault_sync.dart';

/// Folder and file changes that are metadata only (drive-plan.md task 4.7):
/// new folder, rename, move, trash, restore, delete for good. Each is one
/// `ops` call with a fresh `opId` per change, so a repeat after a lost answer
/// does nothing twice; the index follows with a pull.
///
/// A folder's contents go with it: trashing a folder trashes everything in
/// it (the server's 30-day purge only knows trashed objects, so nothing is
/// left behind unreachable), and restoring it brings back what was trashed
/// with it.
class VaultFiles {
  VaultFiles({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    required VaultSync sync,
  }) : _api = api,
       _keys = keys,
       _dao = dao,
       _sync = sync;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final VaultSync _sync;

  /// The server takes at most this many ops per call.
  static const _batch = 500;

  /// Trashed together: within this long of the folder itself.
  static const _sameTrash = 5000;

  Future<String> mkdir(String name, {String? parent}) async {
    final (vaultId, vk) = await _vault();
    _checkName(name);
    final id = Rust.vaultGenerateObjectId();
    final meta = VaultMeta(
      kind: 'dir',
      name: name,
      parent: parent,
      mtimeMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _send(vaultId, [
      {
        'opId': _opId(),
        'type': 'mkdir',
        'objectId': id,
        'encMeta': VaultMetaCodec.seal(vk, vaultId, id, meta),
      },
    ]);
    return id;
  }

  Future<void> rename(String objectId, String name) async {
    final (vaultId, vk) = await _vault();
    _checkName(name);
    final obj = await _object(objectId);
    final meta = VaultMetaCodec.open(vk, vaultId, objectId, obj.encMeta);
    await _send(vaultId, [
      _metaOp(vaultId, vk, objectId, VaultMetaCodec.copy(meta, name: name)),
    ]);
  }

  /// Move [ids] into [parent] (null: the top of the Drive). A folder cannot
  /// go into itself or into one of its own folders.
  Future<void> move(List<String> ids, String? parent) async {
    final (vaultId, vk) = await _vault();
    if (parent != null) {
      final above = await _ancestors(parent);
      if (ids.any((id) => id == parent || above.contains(id))) {
        throw const VaultApiException(
          'VAULT_MOVE_INTO_ITSELF',
          'A folder cannot go into itself',
        );
      }
    }
    final ops = <Map<String, dynamic>>[];
    for (final id in ids) {
      final obj = await _object(id);
      final meta = VaultMetaCodec.open(vk, vaultId, id, obj.encMeta);
      ops.add(
        _metaOp(
          vaultId,
          vk,
          id,
          VaultMetaCodec.copy(meta, parent: parent, root: parent == null),
        ),
      );
    }
    await _send(vaultId, ops);
  }

  Future<void> trash(List<String> ids) async {
    final (vaultId, _) = await _vault();
    final all = <String>{};
    for (final id in ids) {
      all.add(id);
      for (final d in await _descendants(id)) {
        if (d.trashedAt == null) all.add(d.id);
      }
    }
    await _send(vaultId, [
      for (final id in all) {'opId': _opId(), 'type': 'trash', 'objectId': id},
    ]);
  }

  Future<void> restore(List<String> ids) async {
    final (vaultId, _) = await _vault();
    final all = <String>{};
    for (final id in ids) {
      final obj = await _object(id);
      all.add(id);
      final at = obj.trashedAt;
      for (final d in await _descendants(id)) {
        if (d.trashedAt != null &&
            at != null &&
            (d.trashedAt! - at).abs() <= _sameTrash) {
          all.add(d.id);
        }
      }
    }
    await _send(vaultId, [
      for (final id in all)
        {'opId': _opId(), 'type': 'restore', 'objectId': id},
    ]);
  }

  /// Gone for good, with everything inside: the bytes are deleted on the
  /// server once no other object points at them.
  Future<void> deleteForGood(List<String> ids) async {
    final (vaultId, _) = await _vault();
    final all = <String>[];
    for (final id in ids) {
      // Contents first, the folder last.
      all
        ..addAll((await _descendants(id)).map((d) => d.id).toList().reversed)
        ..add(id);
    }
    await _send(vaultId, [
      for (final id in {...all})
        {'opId': _opId(), 'type': 'delete', 'objectId': id},
    ]);
  }

  // ---- helpers -------------------------------------------------------------------

  Future<(String, Uint8List)> _vault() async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) {
      throw const VaultApiException('VAULT_NO_KEY', 'No key on this device');
    }
    return (vaultId, vk);
  }

  Future<VaultObject> _object(String id) async =>
      await _dao.object(id) ??
      (throw const VaultApiException(
        'VAULT_OBJECT_NOT_FOUND',
        'Not in the index',
      ));

  /// Every object below [id], depth first.
  Future<List<VaultObject>> _descendants(String id) async {
    final out = <VaultObject>[];
    final queue = [id];
    while (queue.isNotEmpty) {
      final kids = await _dao.childrenOf(queue.removeLast());
      out.addAll(kids);
      queue.addAll(kids.where((k) => k.kind == 'dir').map((k) => k.id));
    }
    return out;
  }

  Future<Set<String>> _ancestors(String id) async {
    final seen = <String>{};
    String? at = id;
    while (at != null && seen.add(at)) {
      at = (await _dao.object(at))?.parent;
    }
    return seen;
  }

  Map<String, dynamic> _metaOp(
    String vaultId,
    Uint8List vk,
    String objectId,
    VaultMeta meta,
  ) => {
    'opId': _opId(),
    'type': 'meta',
    'objectId': objectId,
    'encMeta': VaultMetaCodec.seal(vk, vaultId, objectId, meta),
  };

  Future<void> _send(String vaultId, List<Map<String, dynamic>> ops) async {
    for (var i = 0; i < ops.length; i += _batch) {
      final r = await _api.ops(
        vaultId,
        ops.sublist(i, i + _batch > ops.length ? ops.length : i + _batch),
      );
      final bad = r.results.where((x) => x['ok'] != true).firstOrNull;
      if (bad != null) {
        await _sync.pull();
        throw VaultApiException(
          bad['code'] as String? ?? 'UNKNOWN',
          bad['message'] as String? ?? '',
        );
      }
    }
    await _sync.pull();
  }

  static void _checkName(String name) {
    if (!VaultMetaCodec.validName(name)) {
      throw const VaultApiException('VAULT_BAD_NAME', 'Not a valid name');
    }
  }

  static String _opId() => Rust.vaultGenerateObjectId();
}
