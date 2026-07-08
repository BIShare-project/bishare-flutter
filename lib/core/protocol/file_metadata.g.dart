// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_metadata.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileMetadata _$FileMetadataFromJson(Map<String, dynamic> json) => FileMetadata(
  id: json['id'] as String,
  fileName: json['fileName'] as String,
  size: (json['size'] as num).toInt(),
  fileType: json['fileType'] as String,
  sha256: json['sha256'] as String?,
  preview: json['preview'] as String?,
  expiresInSeconds: (json['expiresInSeconds'] as num?)?.toInt(),
);

Map<String, dynamic> _$FileMetadataToJson(FileMetadata instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fileName': instance.fileName,
      'size': instance.size,
      'fileType': instance.fileType,
      'sha256': ?instance.sha256,
      'preview': ?instance.preview,
      'expiresInSeconds': ?instance.expiresInSeconds,
    };
