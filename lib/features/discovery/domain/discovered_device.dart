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
    required this.firstSeen,
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

  /// When this peer was first discovered in the current session. Set once on the
  /// first insert and carried across every keep-alive/re-key, NEVER refreshed —
  /// it is the churn-proof key the home grid sorts on so a device keeps its slot
  /// (see [stableDeviceOrder]). Distinct from [lastSeen], which updates constantly.
  final DateTime firstSeen;
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
    firstSeen: firstSeen,
    deviceModel: deviceModel,
    deviceType: deviceType,
    version: version,
    quicPort: quicPort ?? this.quicPort,
    latencyMs: latencyMs ?? this.latencyMs,
  );

  @override
  List<Object?> get props => [fingerprint];
}

/// Deterministic, churn-proof ordering for the nearby-devices grid.
///
/// Sorts by [DiscoveredDevice.firstSeen] (oldest first, so newly-found devices
/// append at the bottom and existing ones never move), with [fingerprint] as a
/// stable tiebreak so two peers discovered in the same instant can never swap.
/// Crucially it is NEVER keyed on liveness/`lastSeen`/discovery timing, so a
/// keep-alive refresh — which re-inserts a peer into the discovery map — cannot
/// make the grid churn or a device jump under the user's finger. O(n log n).
List<DiscoveredDevice> stableDeviceOrder(Iterable<DiscoveredDevice> devices) {
  final ordered = devices.toList();
  ordered.sort((a, b) {
    final byFirstSeen = a.firstSeen.compareTo(b.firstSeen);
    return byFirstSeen != 0
        ? byFirstSeen
        : a.fingerprint.compareTo(b.fingerprint);
  });
  return ordered;
}
