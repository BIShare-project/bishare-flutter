import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/rust/rust_facade.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import '../../../src/rust/api/vault.dart' as rv;
import 'vault_api.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';

/// A link from Drive as this device shows it.
class VaultLink {
  const VaultLink({
    required this.id,
    required this.url,
    required this.folder,
    required this.root,
    required this.name,
    required this.files,
    required this.createdAt,
    required this.expiresAt,
    required this.opens,
  });

  final String id;

  /// The whole link, key included; null when its key cannot be opened here
  /// (a link kept without one).
  final String? url;
  final bool folder;

  /// The shared file or folder, and its name in this device's index (null
  /// when the index no longer has it).
  final String root;
  final String? name;

  /// Files it opens (a folder link: the files under the folder).
  final int files;
  final DateTime createdAt;

  /// Null: until it is turned off.
  final DateTime? expiresAt;
  final int opens;
}

/// Links from Drive (drive-plan.md 6B.3; VAULT-SPEC "Links from Drive"): a
/// file, or a folder with the files under it, that anyone with the link opens
/// in a browser for 1, 7 or 30 days or until it is turned off.
///
/// The device seals a manifest (names, sizes, file keys) with a fresh link key
/// that travels only after `#`; the server keeps that manifest, the ids it
/// covers and the link key sealed with the metadata key, and serves the files
/// straight from the vault. A folder link is the folder as it was when it was
/// last sent: this device sends it again when the folder changes
/// ([refreshFolders], after each sync).
class VaultLinks {
  VaultLinks({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    required SharedPreferences prefs,
  }) : _api = api,
       _keys = keys,
       _dao = dao,
       _prefs = prefs;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final SharedPreferences _prefs;

  static const host = 'https://get.bishare.app/d/';

  /// Files one link may list (the server takes the folder and 1999 files).
  static const maxFiles = 1999;

  /// Folder links this device keeps up to date, with what they listed:
  /// `{linkId: fingerprint}`.
  static const _kFolders = 'vault.folderLinks';

  static String urlOf(String id, Uint8List key) =>
      '$host$id#${base64Url.encode(key).replaceAll('=', '')}';

  Future<({String vaultId, Uint8List vk})> _vault() async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    if (vaultId == null || vk == null) {
      throw const VaultApiException(
        'VAULT_NOT_SIGNED_IN',
        'No Drive account on this device',
      );
    }
    return (vaultId: vaultId, vk: vk);
  }

  /// The files a link over [root] lists, with their paths under it.
  Future<List<rv.VaultLinkFile>> _files(
    VaultObject root,
    String vaultId,
    Uint8List vk,
  ) async {
    rv.VaultLinkFile one(VaultObject o, String path) {
      final meta = VaultMetaCodec.open(vk, vaultId, o.id, o.encMeta);
      return rv.VaultLinkFile(
        objectId: o.id,
        path: path,
        size: meta.size ?? o.size ?? 0,
        mime: meta.mime ?? o.mime ?? 'application/octet-stream',
        mtimeMs: meta.mtimeMs,
        fileKey: meta.fileKey!,
        compression: meta.compression,
        hasThumb: o.hasThumb,
      );
    }

    if (root.kind == 'file') return [one(root, root.name)];
    final out = <rv.VaultLinkFile>[];
    Future<void> walk(String parent, String prefix) async {
      for (final c in await _dao.liveChildren(parent)) {
        if (c.kind == 'dir') {
          await walk(c.id, '$prefix${c.name}/');
        } else {
          out.add(one(c, '$prefix${c.name}'));
          if (out.length > maxFiles) {
            throw const VaultApiException(
              'VAULT_LINK_TOO_MANY',
              'Too many files for one link',
            );
          }
        }
      }
    }

    await walk(root.id, '');
    return out;
  }

  static String _fingerprint(VaultObject root, List<rv.VaultLinkFile> files) {
    final lines = [
      root.name,
      for (final f in files) '${f.objectId}|${f.path}|${f.size}|${f.mtimeMs}',
    ]..sort();
    return crypto.sha256.convert(utf8.encode(lines.join('\n'))).toString();
  }

  ({String manifest, List<String> ids}) _seal(
    VaultObject root,
    List<rv.VaultLinkFile> files,
    String vaultId,
    String linkId,
    Uint8List key,
  ) {
    final folder = root.kind == 'dir';
    return (
      manifest: Rust.vaultSealLink(
        linkKey: key,
        linkId: linkId,
        kind: folder ? 'dir' : 'file',
        name: root.name,
        vaultId: vaultId,
        files: files,
      ),
      ids: [root.id, if (folder) ...files.map((f) => f.objectId)],
    );
  }

  /// A new link over [root]: [days] is 1, 7 or 30, or 0 for until it is
  /// turned off.
  Future<VaultLink> create(VaultObject root, {required int days}) async {
    final (:vaultId, :vk) = await _vault();
    final files = await _files(root, vaultId, vk);
    final linkId = Rust.vaultGenerateObjectId();
    final key = Rust.vaultGenerateLinkKey();
    final sealed = _seal(root, files, vaultId, linkId, key);
    final info = await _api.createLink(
      vaultId,
      linkId: linkId,
      kind: root.kind == 'dir' ? 'folder' : 'file',
      objectIds: sealed.ids,
      manifest: sealed.manifest,
      encKey: Rust.vaultSealLinkKey(
        metaKey: Rust.vaultMetaKey(vk),
        vaultId: vaultId,
        linkId: linkId,
        linkKey: key,
      ),
      days: days,
    );
    if (root.kind == 'dir') {
      await _remember(linkId, _fingerprint(root, files));
    }
    return VaultLink(
      id: linkId,
      url: urlOf(linkId, key),
      folder: root.kind == 'dir',
      root: root.id,
      name: root.name,
      files: files.length,
      createdAt: info.createdAt,
      expiresAt: info.expiresAt,
      opens: 0,
    );
  }

  /// The Drive's links that still open, newest first; only those over
  /// [root] when given.
  Future<List<VaultLink>> list({String? root}) async {
    final (:vaultId, :vk) = await _vault();
    final metaKey = Rust.vaultMetaKey(vk);
    final out = <VaultLink>[];
    for (final l in await _api.links(vaultId)) {
      if (root != null && l.root != root) continue;
      String? url;
      if (l.encKey != null) {
        try {
          url = urlOf(
            l.id,
            Rust.vaultOpenLinkKey(
              metaKey: metaKey,
              vaultId: vaultId,
              linkId: l.id,
              sealed: l.encKey!,
            ),
          );
        } on Object catch (e) {
          debugPrint('[vault] link key: $e');
        }
      }
      final o = await _dao.object(l.root);
      out.add(
        VaultLink(
          id: l.id,
          url: url,
          folder: l.kind == 'folder',
          root: l.root,
          name: o?.name,
          files: l.kind == 'folder' ? l.objects - 1 : 1,
          createdAt: l.createdAt,
          expiresAt: l.expiresAt,
          opens: l.opens,
        ),
      );
    }
    return out;
  }

  /// Turned off: it never opens again.
  Future<void> revoke(String linkId) async {
    final (:vaultId, vk: _) = await _vault();
    await _api.revokeLink(vaultId, linkId);
    await _forget(linkId);
  }

  /// The link mailed to [to] by BIShare; [name] signs it.
  Future<void> email(VaultLink link, {required String to, String? name}) async {
    final url = link.url;
    if (url == null) {
      throw const VaultApiException('VAULT_LINK_NOT_FOUND', 'No key here');
    }
    final (:vaultId, vk: _) = await _vault();
    await _api.emailLink(
      vaultId,
      link.id,
      to: to,
      link: url,
      name: name,
      title: link.name,
    );
  }

  Map<String, String> _folders() {
    try {
      final raw = _prefs.getString(_kFolders);
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } on Object {
      return {};
    }
  }

  Future<void> _remember(String linkId, String print) async {
    final m = _folders()..[linkId] = print;
    await _prefs.setString(_kFolders, jsonEncode(m));
  }

  Future<void> _forget(String linkId) async {
    final m = _folders();
    if (m.remove(linkId) != null) {
      await _prefs.setString(_kFolders, jsonEncode(m));
    }
  }

  /// Sends again every folder link this device keeps whose folder changed
  /// since it was last sent. Links found gone are dropped from the list.
  Future<int> refreshFolders() async {
    final known = _folders();
    if (known.isEmpty) return 0;
    final (:vaultId, :vk) = await _vault();
    var sent = 0;
    final links = {for (final l in await _api.links(vaultId)) l.id: l};
    for (final MapEntry(key: id, value: print) in known.entries) {
      final l = links[id];
      if (l == null || l.kind != 'folder' || l.encKey == null) {
        await _forget(id);
        continue;
      }
      final root = await _dao.object(l.root);
      // The folder went to the trash or is gone: its link has stopped
      // opening by itself.
      if (root == null || root.trashedAt != null) continue;
      try {
        final files = await _files(root, vaultId, vk);
        final now = _fingerprint(root, files);
        if (now == print) continue;
        final key = Rust.vaultOpenLinkKey(
          metaKey: Rust.vaultMetaKey(vk),
          vaultId: vaultId,
          linkId: id,
          sealed: l.encKey!,
        );
        final sealed = _seal(root, files, vaultId, id, key);
        await _api.updateLink(
          vaultId,
          id,
          kind: 'folder',
          objectIds: sealed.ids,
          manifest: sealed.manifest,
        );
        await _remember(id, now);
        sent++;
      } on VaultApiException catch (e) {
        if (e.code == 'VAULT_LINK_NOT_FOUND') await _forget(id);
        debugPrint('[vault] folder link $id: ${e.code}');
      }
    }
    return sent;
  }
}
