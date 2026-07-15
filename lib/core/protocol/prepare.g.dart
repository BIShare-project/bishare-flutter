// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'prepare.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PrepareRequest _$PrepareRequestFromJson(Map<String, dynamic> json) =>
    PrepareRequest(
      info: DeviceInfo.fromJson(json['info'] as Map<String, dynamic>),
      files: (json['files'] as Map<String, dynamic>).map(
        (k, e) => MapEntry(k, FileMetadata.fromJson(e as Map<String, dynamic>)),
      ),
      syncPairId: json['syncPairId'] as String?,
    );

Map<String, dynamic> _$PrepareRequestToJson(PrepareRequest instance) =>
    <String, dynamic>{
      'info': instance.info.toJson(),
      'files': instance.files.map((k, e) => MapEntry(k, e.toJson())),
      'syncPairId': ?instance.syncPairId,
    };

PrepareResponse _$PrepareResponseFromJson(Map<String, dynamic> json) =>
    PrepareResponse(
      sessionId: json['sessionId'] as String,
      files: Map<String, String>.from(json['files'] as Map),
      publicKey: json['publicKey'] as String?,
      maxConcurrent: (json['maxConcurrent'] as num?)?.toInt(),
      chunkSize: (json['chunkSize'] as num?)?.toInt(),
      windowSize: (json['windowSize'] as num?)?.toInt(),
      supportsCompression: json['supportsCompression'] as bool?,
      keepAlive: json['keepAlive'] as bool?,
      streamsPerFile: (json['streamsPerFile'] as num?)?.toInt(),
      supportsResume: json['supportsResume'] as bool?,
    );

Map<String, dynamic> _$PrepareResponseToJson(PrepareResponse instance) =>
    <String, dynamic>{
      'sessionId': instance.sessionId,
      'files': instance.files,
      'publicKey': ?instance.publicKey,
      'maxConcurrent': ?instance.maxConcurrent,
      'chunkSize': ?instance.chunkSize,
      'windowSize': ?instance.windowSize,
      'supportsCompression': ?instance.supportsCompression,
      'keepAlive': ?instance.keepAlive,
      'streamsPerFile': ?instance.streamsPerFile,
      'supportsResume': ?instance.supportsResume,
    };
