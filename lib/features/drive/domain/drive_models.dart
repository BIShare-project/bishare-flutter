/// Drive domain models, grounded to §C/§D/§E of the frozen API contract. Plain
/// immutable classes with manual JSON — matching the app's existing DTO style
/// (`AuthUser`, `CloudUploadResult`, `ReceivedFile`) rather than pulling freezed
/// codegen in, so this feature stays consistent with Fase A and codegen-free.
library;

int _int(Object? v) => v is num ? v.toInt() : 0;
double _double(Object? v) => v is num ? v.toDouble() : 0;
String _str(Object? v) => v is String ? v : '';
String? _optStr(Object? v) => v is String && v.isNotEmpty ? v : null;

/// A folder — mirrors the backend `folderResponse` (`parent_id` present only
/// when the folder is not at the root).
class DriveFolder {
  const DriveFolder({
    required this.id,
    required this.name,
    this.parentId,
    this.depth = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String id;
  final String name;
  final String? parentId;
  final int depth;
  final String createdAt;
  final String updatedAt;

  factory DriveFolder.fromJson(Map<String, dynamic> json) => DriveFolder(
    id: _str(json['id']),
    name: _str(json['name']),
    parentId: _optStr(json['parent_id']),
    depth: _int(json['depth']),
    createdAt: _str(json['created_at']),
    updatedAt: _str(json['updated_at']),
  );
}

/// A file — covers both `fileResponse` and `fileResponseReduced` (the reduced
/// form omits `checksum_sha256`/`deleted_at`; trash rows carry `deleted_at`).
class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.size,
    required this.mimeType,
    this.folderId,
    this.checksumSha256,
    this.deletedAt,
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String id;
  final String name;
  final int size;
  final String mimeType;
  final String? folderId;
  final String? checksumSha256;
  final String? deletedAt;
  final String createdAt;
  final String updatedAt;

  factory DriveFile.fromJson(Map<String, dynamic> json) => DriveFile(
    id: _str(json['id']),
    name: _str(json['name']),
    size: _int(json['size']),
    mimeType: _str(json['mime_type']),
    folderId: _optStr(json['folder_id']),
    checksumSha256: _optStr(json['checksum_sha256']),
    deletedAt: _optStr(json['deleted_at']),
    createdAt: _str(json['created_at']),
    updatedAt: _str(json['updated_at']),
  );
}

/// One page of a paginated `GET /files` response.
class DriveFilePage {
  const DriveFilePage({
    required this.files,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  final List<DriveFile> files;
  final int page;
  final int totalPages;
  final int total;

  bool get hasMore => page < totalPages;
}

/// One category row of the storage by-type breakdown.
class StorageCategory {
  const StorageCategory({
    required this.category,
    required this.size,
    required this.count,
  });

  final String category;
  final int size;
  final int count;

  factory StorageCategory.fromJson(Map<String, dynamic> json) =>
      StorageCategory(
        category: _str(json['category']),
        size: _int(json['size']),
        count: _int(json['count']),
      );
}

/// `GET /storage/usage` — quota counters + by-type breakdown.
class StorageUsage {
  const StorageUsage({
    required this.used,
    required this.limit,
    required this.tier,
    required this.usedPercent,
    this.byType = const [],
  });

  final int used;
  final int limit;
  final String tier;
  final double usedPercent;
  final List<StorageCategory> byType;

  /// Clamped 0..1 fraction for a progress bar (limit==0 → 0).
  double get fraction => limit > 0 ? (used / limit).clamp(0, 1).toDouble() : 0;

  factory StorageUsage.fromJson(Map<String, dynamic> json) => StorageUsage(
    used: _int(json['used']),
    limit: _int(json['limit']),
    tier: _str(json['tier']),
    usedPercent: _double(json['used_percent']),
    byType: [
      for (final c in (json['by_type'] as List? ?? const []))
        if (c is Map<String, dynamic>) StorageCategory.fromJson(c),
    ],
  );
}

/// A share-link — mirrors `shareResponse`. `url` is the full, copyable
/// `https://bishare.app/share/<token>` produced by the backend.
class ShareLink {
  const ShareLink({
    required this.id,
    required this.token,
    required this.url,
    this.fileId,
    this.folderId,
    this.hasPassword = false,
    this.expiresAt,
    this.maxDownloads,
    this.downloadCount = 0,
    this.createdAt = '',
  });

  final String id;
  final String token;
  final String url;
  final String? fileId;
  final String? folderId;
  final bool hasPassword;
  final String? expiresAt;
  final int? maxDownloads;
  final int downloadCount;
  final String createdAt;

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
    id: _str(json['id']),
    token: _str(json['token']),
    url: _str(json['url']),
    fileId: _optStr(json['file_id']),
    folderId: _optStr(json['folder_id']),
    hasPassword: json['has_password'] == true,
    expiresAt: _optStr(json['expires_at']),
    maxDownloads: json['max_downloads'] is num
        ? (json['max_downloads'] as num).toInt()
        : null,
    downloadCount: _int(json['download_count']),
    createdAt: _str(json['created_at']),
  );
}
