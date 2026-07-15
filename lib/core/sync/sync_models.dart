/// Plain Dart mirrors of the folder-sync wire structs
/// (`bishare_protocol::binary`), used on both the LAN and cloud paths. Kept as
/// hand-written value types (not the FRB-generated `FfiScanEntry`) so the engine
/// has one manifest model it can serialize to the exact JSON `manifestDiff`
/// expects and parse the ops back from — independent of how a batch was sourced
/// (scanner, a peer frame, or a decrypted cloud manifest).
library;

/// One manifest row — a file or directory currently under a pair root.
/// Serializes to the `BinaryManifestEntry` JSON (`sha256` omitted when null;
/// `isDir` always present so an empty file is never confused with a directory).
class ManifestEntry {
  const ManifestEntry({
    required this.path,
    required this.size,
    required this.mtimeMs,
    this.sha256,
    this.isDir = false,
  });

  /// Path relative to the pair root, forward-slashed.
  final String path;
  final int size;
  final int mtimeMs;

  /// Lowercase-hex SHA-256 of the content; null for directories and for files
  /// not yet hashed (deferred as unstable).
  final String? sha256;
  final bool isDir;

  Map<String, dynamic> toJson() => {
    'path': path,
    'size': size,
    'mtimeMs': mtimeMs,
    'isDir': isDir,
    if (sha256 != null) 'sha256': sha256,
  };

  factory ManifestEntry.fromJson(Map<String, dynamic> j) => ManifestEntry(
    path: j['path'] as String,
    size: (j['size'] as num).toInt(),
    mtimeMs: (j['mtimeMs'] as num).toInt(),
    sha256: j['sha256'] as String?,
    isDir: (j['isDir'] as bool?) ?? false,
  );

  ManifestEntry copyWith({String? sha256}) => ManifestEntry(
    path: path,
    size: size,
    mtimeMs: mtimeMs,
    sha256: sha256 ?? this.sha256,
    isDir: isDir,
  );
}

/// The four delta operations that transform one manifest into another
/// (`manifest_diff` output). `rename` and `delete` move no file bytes (§5.1).
enum SyncOpKind {
  add,
  modify,
  delete,
  rename,

  /// An op string the current build doesn't know — never acted on (forward
  /// compatibility with a newer peer), only logged.
  unknown;

  static SyncOpKind parse(String? s) => switch (s) {
    'add' => SyncOpKind.add,
    'modify' => SyncOpKind.modify,
    'delete' => SyncOpKind.delete,
    'rename' => SyncOpKind.rename,
    _ => SyncOpKind.unknown,
  };

  String get wire => switch (this) {
    SyncOpKind.add => 'add',
    SyncOpKind.modify => 'modify',
    SyncOpKind.delete => 'delete',
    SyncOpKind.rename => 'rename',
    SyncOpKind.unknown => 'unknown',
  };
}

/// A single change to apply to a manifest/tree. `path` is the existing/old path;
/// for a `rename` the file is at `newPath` afterwards.
class DeltaOp {
  const DeltaOp({
    required this.kind,
    required this.path,
    this.newPath,
    this.sha256,
    this.size,
    this.mtimeMs,
    this.isDir,
  });

  final SyncOpKind kind;
  final String path;
  final String? newPath;
  final String? sha256;
  final int? size;
  final int? mtimeMs;
  final bool? isDir;

  bool get isDirectory => isDir ?? false;

  /// True for ops that transfer no file content — the receiver applies them by
  /// touching the filesystem only (delete → trash, rename → move). Add/modify
  /// still need the bytes (LAN payload or a cloud blob).
  bool get isMetadataOnly =>
      kind == SyncOpKind.delete || kind == SyncOpKind.rename;

  factory DeltaOp.fromJson(Map<String, dynamic> j) => DeltaOp(
    kind: SyncOpKind.parse(j['op'] as String?),
    path: j['path'] as String,
    newPath: j['newPath'] as String?,
    sha256: j['sha256'] as String?,
    size: (j['size'] as num?)?.toInt(),
    mtimeMs: (j['mtimeMs'] as num?)?.toInt(),
    isDir: j['isDir'] as bool?,
  );

  Map<String, dynamic> toJson() => {
    'op': kind.wire,
    'path': path,
    if (newPath != null) 'newPath': newPath,
    if (sha256 != null) 'sha256': sha256,
    if (size != null) 'size': size,
    if (mtimeMs != null) 'mtimeMs': mtimeMs,
    if (isDir != null) 'isDir': isDir,
  };
}
