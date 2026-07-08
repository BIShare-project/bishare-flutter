import 'package:json_annotation/json_annotation.dart';

import 'device_info.dart';
import 'file_metadata.dart';

part 'prepare.g.dart';

/// Request body for `POST /api/v1/prepare`. `files` is keyed by fileId.
@JsonSerializable(explicitToJson: true)
class PrepareRequest {
  const PrepareRequest({required this.info, required this.files});

  factory PrepareRequest.fromJson(Map<String, dynamic> json) =>
      _$PrepareRequestFromJson(json);

  final DeviceInfo info;
  final Map<String, FileMetadata> files;

  Map<String, dynamic> toJson() => _$PrepareRequestToJson(this);
}

/// Response body from `POST /api/v1/prepare`. `files` maps fileId → upload token.
/// A non-null [publicKey] signals the sender to derive an E2E key and encrypt.
@JsonSerializable(includeIfNull: false)
class PrepareResponse {
  const PrepareResponse({
    required this.sessionId,
    required this.files,
    this.publicKey,
    this.maxConcurrent,
    this.chunkSize,
    this.windowSize,
    this.supportsCompression,
    this.keepAlive,
    this.streamsPerFile,
  });

  factory PrepareResponse.fromJson(Map<String, dynamic> json) =>
      _$PrepareResponseFromJson(json);

  final String sessionId;
  final Map<String, String> files;
  final String? publicKey;
  final int? maxConcurrent;
  final int? chunkSize;
  final int? windowSize;
  final bool? supportsCompression;
  final bool? keepAlive;
  final int? streamsPerFile;

  Map<String, dynamic> toJson() => _$PrepareResponseToJson(this);
}
