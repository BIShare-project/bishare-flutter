import 'dart:convert';
import 'dart:typed_data';

import '../../../core/rust/rust_facade.dart';
import '../../../src/rust/api/vault.dart' show VaultMeta;

export '../../../src/rust/api/vault.dart' show VaultMeta;

/// Small helpers around VAULT-SPEC "Object metadata" and "Compression".
abstract final class VaultMetaCodec {
  /// Seal [meta] for [objectId] of [vaultId] under the vault key.
  static String seal(
    Uint8List vaultKey,
    String vaultId,
    String objectId,
    VaultMeta meta,
  ) => Rust.vaultSealMeta(
    metaKey: Rust.vaultMetaKey(vaultKey),
    vaultId: vaultId,
    objectId: objectId,
    meta: meta,
  );

  /// Open the sealed metadata of one object. Throws when it does not open.
  static VaultMeta open(
    Uint8List vaultKey,
    String vaultId,
    String objectId,
    String encMeta,
  ) => Rust.vaultOpenMeta(
    metaKey: Rust.vaultMetaKey(vaultKey),
    vaultId: vaultId,
    objectId: objectId,
    encMeta: encMeta,
  );

  /// The same metadata with some fields changed (rename, move).
  static VaultMeta copy(
    VaultMeta m, {
    String? name,
    String? parent,
    bool root = false,
    int? mtimeMs,
  }) => VaultMeta(
    kind: m.kind,
    name: name ?? m.name,
    parent: root ? null : (parent ?? m.parent),
    mtimeMs: mtimeMs ?? m.mtimeMs,
    size: m.size,
    mime: m.mime,
    fileKey: m.fileKey,
    hash: m.hash,
    compression: m.compression,
  );

  static String b64u(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  /// A name the spec accepts: not empty, no `/`, no U+0000.
  static bool validName(String name) =>
      name.isNotEmpty && !name.contains('/') && !name.contains('\u0000');

  /// Largest file compressed before sealing: compression runs in memory.
  static const compressMax = 64 * 1024 * 1024;

  /// Types worth compressing (VAULT-SPEC "Compression"): documents, text,
  /// code, CSV, uncompressed audio and images, PSD. Already-compressed formats
  /// (JPEG, PNG, video, ZIP, Office's own zip containers) are left alone.
  static bool compressible(String mime, String name) {
    final m = mime.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (m.startsWith('text/')) return true;
    const types = {
      'application/json',
      'application/xml',
      'application/javascript',
      'application/x-sh',
      'application/sql',
      'application/rtf',
      'application/pdf',
      'application/x-tar',
      'application/vnd.adobe.photoshop',
      'image/bmp',
      'image/tiff',
      'image/x-ms-bmp',
      'image/svg+xml',
      'audio/wav',
      'audio/x-wav',
      'audio/aiff',
      'audio/x-aiff',
    };
    if (types.contains(m)) return true;
    const exts = {
      'txt',
      'md',
      'csv',
      'tsv',
      'json',
      'xml',
      'yaml',
      'yml',
      'log',
      'html',
      'css',
      'js',
      'ts',
      'dart',
      'py',
      'java',
      'kt',
      'swift',
      'c',
      'h',
      'cpp',
      'rs',
      'go',
      'rb',
      'php',
      'sql',
      'sh',
      'ini',
      'toml',
      'psd',
      'bmp',
      'tif',
      'tiff',
      'wav',
      'aif',
      'aiff',
      'svg',
      'rtf',
      'tex',
      'srt',
      'vtt',
    };
    return exts.contains(ext);
  }
}
