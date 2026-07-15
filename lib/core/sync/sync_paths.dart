/// Path safety for folder-sync relative paths (wire → filesystem). Shared by
/// the receiver's upload routing (`TransferServer`) and the op applier
/// (`SyncEngine`) so both enforce identical rules.
library;

import 'dart:io';

/// Join [rel] (forward-slashed, from the wire) under [root], rejecting
/// traversal and absolute inputs: no `..`/`.`/empty segments, no leading `/`,
/// no `:` (drive letters / alternate streams). Returns null — the caller skips
/// the op/file — rather than throwing: a malicious peer must not be able to
/// fault the receiver, only to be ignored.
String? safeSyncJoin(String root, String rel) {
  if (rel.isEmpty) return null;
  final norm = rel.replaceAll('\\', '/');
  if (norm.startsWith('/') || norm.contains(':')) return null;
  final segs = norm.split('/');
  if (segs.any((s) => s == '..' || s.isEmpty || s == '.')) return null;
  return '$root${Platform.pathSeparator}${segs.join(Platform.pathSeparator)}';
}
