import 'package:equatable/equatable.dart';

/// Lifecycle of a nearby (MultipeerConnectivity) peer, mirroring the native
/// `PeerState`.
enum NearbyPeerState { discovered, connecting, connected, transferring, completed, failed }

/// A device discovered over the offline `bishare-nearby` MPC service. [id] is the
/// MCPeerID displayName (stable within a session); [alias] is the friendly name
/// from the peer's discoveryInfo.
class NearbyPeer extends Equatable {
  const NearbyPeer({
    required this.id,
    required this.alias,
    this.state = NearbyPeerState.discovered,
  });

  final String id;
  final String alias;
  final NearbyPeerState state;

  bool get isBusy =>
      state == NearbyPeerState.connecting || state == NearbyPeerState.transferring;

  NearbyPeer copyWith({NearbyPeerState? state}) =>
      NearbyPeer(id: id, alias: alias, state: state ?? this.state);

  /// Maps the native state string emitted over the event channel.
  static NearbyPeerState stateFrom(String? s) => switch (s) {
    'connecting' => NearbyPeerState.connecting,
    'connected' => NearbyPeerState.connected,
    'transferring' => NearbyPeerState.transferring,
    'completed' => NearbyPeerState.completed,
    'failed' => NearbyPeerState.failed,
    _ => NearbyPeerState.discovered,
  };

  static NearbyPeer fromMap(Map<String, dynamic> m) => NearbyPeer(
    id: m['id'] as String,
    alias: (m['alias'] as String?) ?? (m['id'] as String),
    state: stateFrom(m['state'] as String?),
  );

  @override
  List<Object?> get props => [id, alias, state];
}
