import 'package:json_annotation/json_annotation.dart';

part 'file_metadata.g.dart';

/// Wire model describing one file in a prepare request. Mirrors native
/// `FileMetadata` exactly. `size` is a 64-bit byte count.
@JsonSerializable(includeIfNull: false)
class FileMetadata {
  const FileMetadata({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    this.sha256,
    this.preview,
    this.expiresInSeconds,
  });

  factory FileMetadata.fromJson(Map<String, dynamic> json) =>
      _$FileMetadataFromJson(json);

  final String id;
  final String fileName;
  final int size;
  final String fileType;
  final String? sha256;

  /// Optional base64 thumbnail (small images only).
  final String? preview;

  /// Self-destruct TTL in seconds (null = never).
  final int? expiresInSeconds;

  Map<String, dynamic> toJson() => _$FileMetadataToJson(this);
}
