// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceInfo _$DeviceInfoFromJson(Map<String, dynamic> json) => DeviceInfo(
  alias: json['alias'] as String,
  version: json['version'] as String,
  fingerprint: json['fingerprint'] as String,
  port: (json['port'] as num).toInt(),
  protocol: json['protocol'] as String? ?? BIShareProtocolScheme.https,
  download: json['download'] as bool? ?? false,
  deviceModel: json['deviceModel'] as String?,
  deviceType: json['deviceType'] as String?,
  publicKey: json['publicKey'] as String?,
  supportsBinary: json['supportsBinary'] as bool?,
  supportsCompression: json['supportsCompression'] as bool?,
  supportsKeepAlive: json['supportsKeepAlive'] as bool?,
  supportsSync: json['supportsSync'] as bool?,
  supportsBroadcast: json['supportsBroadcast'] as bool?,
  supportsMedia: json['supportsMedia'] as bool?,
  supportsResumeOffset: json['supportsResumeOffset'] as bool?,
  supportsClipboardBinary: json['supportsClipboardBinary'] as bool?,
  ip: json['ip'] as String?,
);

Map<String, dynamic> _$DeviceInfoToJson(DeviceInfo instance) =>
    <String, dynamic>{
      'alias': instance.alias,
      'version': instance.version,
      'fingerprint': instance.fingerprint,
      'port': instance.port,
      'protocol': instance.protocol,
      'download': instance.download,
      'deviceModel': ?instance.deviceModel,
      'deviceType': ?instance.deviceType,
      'publicKey': ?instance.publicKey,
      'supportsBinary': ?instance.supportsBinary,
      'supportsCompression': ?instance.supportsCompression,
      'supportsKeepAlive': ?instance.supportsKeepAlive,
      'supportsSync': ?instance.supportsSync,
      'supportsBroadcast': ?instance.supportsBroadcast,
      'supportsMedia': ?instance.supportsMedia,
      'supportsResumeOffset': ?instance.supportsResumeOffset,
      'supportsClipboardBinary': ?instance.supportsClipboardBinary,
      'ip': ?instance.ip,
    };
