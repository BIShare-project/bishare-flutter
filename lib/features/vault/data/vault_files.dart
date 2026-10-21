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
    name = await freeName(_dao, parent, name);
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
    if (name.toLowerCase() != obj.name.toLowerCase()) {
      name = await freeName(_dao, obj.parent, name);
    }
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
    final taken = <String>{};
    for (final id in ids) {
      final obj = await _object(id);
      if (obj.parent == parent) continue;
      final meta = VaultMetaCodec.open(vk, vaultId, id, obj.encMeta);
      final name = await freeName(_dao, parent, obj.name, taken: taken);
      taken.add(name.toLowerCase());
      ops.add(
        _metaOp(
          vaultId,
          vk,
          id,
          VaultMetaCodec.copy(
            meta,
            name: name,
            parent: parent,
            root: parent == null,
          ),
        ),
      );
    }
    if (ops.isEmpty) return;
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

  /// Bring [ids] back with what was trashed with them: the folder's contents
  /// trashed at the same time or after it (a large folder goes to the trash
  /// in several calls), not what was trashed on its own before.
  Future<void> restore(List<String> ids) async {
    final (vaultId, _) = await _vault();
    final all = <String>{};
    for (final id in ids) {
      final obj = await _object(id);
      all.add(id);
      final at = obj.trashedAt;
      if (at == null) continue;
      for (final d in await _trashedBelow(id)) {
        if (d.trashedAt! >= at - _sameTrash) all.add(d.id);
      }
    }
    await _send(vaultId, [
      for (final id in all)
        {'opId': _opId(), 'type': 'restore', 'objectId': id},
    ]);
  }

  /// Copy [ids] into [parent] (null: the top of the Drive). Nothing is sent
  /// again: a copied file is a new object pointing at the same stored bytes
  /// with the same file key, and a folder is copied with everything in it.
  /// A name already used in the target gets " (1)", " (2)", ….
  Future<List<String>> copy(List<String> ids, String? parent) async {
    final (vaultId, vk) = await _vault();
    final ops = <Map<String, dynamic>>[];
    final made = <String>[];
    final taken = <String>{};

    Future<void> copyOne(
      VaultObject o,
      String? into, {
      bool top = false,
    }) async {
      final meta = VaultMetaCodec.open(vk, vaultId, o.id, o.encMeta);
      final name = top
          ? await freeName(_dao, into, o.name, taken: taken)
          : o.name;
      if (top) taken.add(name.toLowerCase());
      final id = Rust.vaultGenerateObjectId();
      if (top) made.add(id);
      final copied = VaultMetaCodec.copy(
        meta,
        name: name,
        parent: into,
        root: into == null,
      );
      if (o.kind == 'dir') {
        ops.add({
          'opId': _opId(),
          'type': 'mkdir',
          'objectId': id,
          'encMeta': VaultMetaCodec.seal(vk, vaultId, id, copied),
        });
        for (final child in await _dao.childrenOf(o.id)) {
          if (child.trashedAt == null) await copyOne(child, id);
        }
      } else {
        if (o.blobId == null) return;
        ops.add({
          'opId': _opId(),
          'type': 'link',
          'objectId': id,
          'encMeta': VaultMetaCodec.seal(vk, vaultId, id, copied),
          'blobId': o.blobId,
        });
      }
    }

    if (parent != null) {
      final above = await _ancestors(parent);
      if (ids.any((id) => id == parent || above.contains(id))) {
        throw const VaultApiException(
          'VAULT_MOVE_INTO_ITSELF',
          'A folder cannot go into itself',
        );
      }
    }
    for (final id in ids) {
      await copyOne(await _object(id), parent, top: true);
    }
    await _send(vaultId, ops);
    return made;
  }

  /// Gone for good, with what is in the trash inside them: the bytes are
  /// deleted on the server once no other object points at them. Only what
  /// is in the trash can go. Something live inside a trashed folder (restored
  /// on its own, or added from a device that had not seen the trash yet) is
  /// kept and moves to the top of the Drive.
  Future<void> deleteForGood(List<String> ids) async {
    final (vaultId, _) = await _vault();
    final gone = <String>[];
    final keep = <String>[];
    for (final id in ids) {
      final obj = await _dao.object(id);
      if (obj == null || obj.trashedAt == null) continue;
      final below = await _trashedBelow(id, live: keep);
      // Contents first, the folder last.
      gone
        ..addAll(below.map((d) => d.id).toList().reversed)
        ..add(id);
    }
    if (keep.isNotEmpty) await move(keep, null);
    if (gone.isEmpty) return;
    await _send(vaultId, [
      for (final id in {...gone})
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

  /// The trashed objects below [id], reached through trashed folders only
  /// (parents before children). Live children met on the way go to [live].
  Future<List<VaultObject>> _trashedBelow(
    String id, {
    List<String>? live,
  }) async {
    final out = <VaultObject>[];
    final queue = [id];
    while (queue.isNotEmpty) {
      for (final k in await _dao.childrenOf(queue.removeLast())) {
        if (k.trashedAt == null) {
          live?.add(k.id);
          continue;
        }
        out.add(k);
        if (k.kind == 'dir') queue.add(k.id);
      }
    }
    return out;
  }

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

/// [name], or "name (1).ext", "name (2).ext", … whichever is not used yet by
/// a live object in [parent] (names compare without case, as on macOS and
/// Windows), nor in [taken] (lower case).
Future<String> freeName(
  VaultDao dao,
  String? parent,
  String name, {
  Set<String> taken = const {},
}) async => freeNameIn({
  ...taken,
  for (final o in await dao.liveChildren(parent)) o.name.toLowerCase(),
}, name);

/// The same, against a set of lower-case names already in use.
String freeNameIn(Set<String> used, String name) {
  if (!used.contains(name.toLowerCase())) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var n = 1; ; n++) {
    final candidate = '$stem ($n)$ext';
    if (!used.contains(candidate.toLowerCase())) return candidate;
  }
}
