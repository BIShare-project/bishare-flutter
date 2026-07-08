import 'package:equatable/equatable.dart';

/// A peer found on the local network. Identity is its [fingerprint]; [host] is a
/// routable IPv4 (self-reported via the TXT `ip` attribute — the discovery fix).
class DiscoveredDevice extends Equatable {
  const DiscoveredDevice({
    required this.fingerprint,
    required this.alias,
    required this.host,
    required this.port,
    required this.lastSeen,
    this.deviceModel = '',
    this.deviceType = 'mobile',
    this.version = '2.0',
    this.quicPort,
    this.latencyMs = 0,
  });

  final String fingerprint;
  final String alias;
  final String host;
  final int port;
  final DateTime lastSeen;
  final String deviceModel;
  final String deviceType;
  final String version;
  final int? quicPort;
  final int latencyMs;

  bool get supportsQuic => quicPort != null;

  DiscoveredDevice copyWith({
    String? host,
    int? port,
    DateTime? lastSeen,
    int? quicPort,
    int? latencyMs,
  }) => DiscoveredDevice(
    fingerprint: fingerprint,
    alias: alias,
    host: host ?? this.host,
    port: port ?? this.port,
    lastSeen: lastSeen ?? this.lastSeen,
    deviceModel: deviceModel,
    deviceType: deviceType,
    version: version,
    quicPort: quicPort ?? this.quicPort,
    latencyMs: latencyMs ?? this.latencyMs,
  );

  @override
  List<Object?> get props => [fingerprint];
}
