import 'package:json_annotation/json_annotation.dart';

import 'device_info.dart';
import 'file_metadata.dart';

part 'prepare.g.dart';

/// Request body for `POST /api/v1/prepare`. `files` is keyed by fileId.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class PrepareRequest {
  const PrepareRequest({required this.info, required this.files, this.syncPairId});

  factory PrepareRequest.fromJson(Map<String, dynamic> json) =>
      _$PrepareRequestFromJson(json);

  final DeviceInfo info;
  final Map<String, FileMetadata> files;

  /// Folder-sync payload marker (Tahap 4): when set, this prepare carries files
  /// for the given sync pair — the receiver auto-accepts if (pairId, sender
  /// fingerprint) matches a configured pair, and routes each file to the pair
  /// root at its [FileMetadata.relPath] instead of the inbox. Older peers
  /// ignore the field (it's absent from normal transfers).
  final String? syncPairId;

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
    this.supportsResume,
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

  /// Phase 4: this receiver keeps a durable resume ledger, so a v2.3+ QUIC
  /// sender may use the resume (V2) control protocol to skip already-received
  /// chunks after a reconnect. Absent/false → sender uses the non-resume path.
  final bool? supportsResume;

  Map<String, dynamic> toJson() => _$PrepareResponseToJson(this);
}
