import 'package:json_annotation/json_annotation.dart';

part 'device_info.g.dart';

/// Wire model for `GET /api/v1/info` and the `info` field of a prepare request.
/// Field names mirror the native `DeviceInfo` Codable exactly (note `protocol`).
@JsonSerializable(includeIfNull: false)
class DeviceInfo {
  const DeviceInfo({
    required this.alias,
    required this.version,
    required this.fingerprint,
    required this.port,
    this.protocol = BIShareProtocolScheme.https,
    this.download = false,
    this.deviceModel,
    this.deviceType,
    this.publicKey,
    this.supportsBinary,
    this.supportsCompression,
    this.supportsKeepAlive,
    this.ip,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) =>
      _$DeviceInfoFromJson(json);

  final String alias;
  final String version;
  final String fingerprint;
  final int port;

  @JsonKey(name: 'protocol')
  final String protocol;

  final bool download;
  final String? deviceModel;
  final String? deviceType;
  final String? publicKey;
  final bool? supportsBinary;
  final bool? supportsCompression;
  final bool? supportsKeepAlive;

  /// Self-reported LAN IPv4 — the fix that makes discovery reliable over
  /// Apple AWDL (peers must not rely on the transport-resolved IPv6 endpoint).
  final String? ip;

  Map<String, dynamic> toJson() => _$DeviceInfoToJson(this);
}

/// Kept as a plain string constant to match the native `protocol` value.
class BIShareProtocolScheme {
  BIShareProtocolScheme._();
  static const String https = 'https';
}
