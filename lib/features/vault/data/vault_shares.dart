import 'dart:io';

import 'package:mime/mime.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/crypto/bse2.dart';
import '../../../core/storage/vault_tables.dart';
import '../../remote/data/cloud_transfer_service.dart';
import 'vault_api.dart';
import 'vault_downloads.dart';
import 'vault_keys.dart';
import 'vault_meta.dart';

/// A Drive file as a transfer link (drive-plan.md task 4.10, "Sharing a
/// Drive file"): the server copies the stored ciphertext into the transfer
/// bucket, and the link carries the file key after `#`, which browsers never
/// send anywhere. The Drive copy is untouched when the link expires.
///
/// A file stored compressed cannot go that way: the download page would open
/// DEFLATE bytes. Those are fetched, inflated and uploaded as an ordinary
/// encrypted transfer instead (always 24 hours, like every link the app
/// makes); they are at most 64 MB.
class VaultShares {
  VaultShares({
    required VaultApi api,
    required VaultKeyStore keys,
    required VaultDao dao,
    required VaultDownloads downloads,
    required CloudTransferService Function() cloud,
    required String Function() senderAlias,
  }) : _api = api,
       _keys = keys,
       _dao = dao,
       _downloads = downloads,
       _cloud = cloud,
       _alias = senderAlias;

  final VaultApi _api;
  final VaultKeyStore _keys;
  final VaultDao _dao;
  final VaultDownloads _downloads;

  /// Only for files stored compressed (see above).
  final CloudTransferService Function() _cloud;
  final String Function() _alias;

  /// The link, and when it stops working.
  Future<({String url, DateTime? expiresAt, bool viaUpload})> share(
    String objectId, {
    required int hours,
    bool oneTime = false,
  }) async {
    final vaultId = await _keys.vaultId();
    final vk = await _keys.vaultKey();
    final o = await _dao.object(objectId);
    if (vaultId == null || vk == null || o == null || o.kind != 'file') {
      throw const VaultApiException('VAULT_OBJECT_NOT_FOUND', 'Not a file');
    }
    final meta = VaultMetaCodec.open(vk, vaultId, objectId, o.encMeta);
    final mime =
        meta.mime ?? lookupMimeType(o.name) ?? 'application/octet-stream';
    if (meta.compression == 'deflate') {
      final dir = await VaultDownloads.cacheFor('share', objectId);
      final plain = await _downloads.file(
        o,
        File('${dir.path}/${VaultDownloads.safeName(o.name)}'),
        listed: false,
      );
      if (plain == null) {
        throw const VaultApiException('UNKNOWN', 'The file did not download');
      }
      try {
        final r = await _cloud().uploadTransfer(
          file: plain,
          fileName: o.name,
          mimeType: mime,
          senderAlias: _alias(),
          oneTime: oneTime,
        );
        return (url: r.url, expiresAt: r.expiresAt, viaUpload: true);
      } finally {
        try {
          await dir.delete(recursive: true);
        } on Object {
          // Cache.
        }
      }
    }
    final s = await _api.share(
      vaultId,
      objectId: objectId,
      fileName: o.name,
      mimeType: mime,
      expiryHours: hours,
      oneTime: oneTime,
      mtimeMs: meta.mtimeMs,
    );
    return (
      url:
          '${CloudConfig.transferWebUrl(s.rawCode)}#k=${Bse2.encodeKey(meta.fileKey!)}',
      expiresAt: s.expiresAt,
      viaUpload: false,
    );
  }
}
