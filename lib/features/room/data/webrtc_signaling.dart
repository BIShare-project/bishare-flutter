import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../../core/constants/cloud.dart';

/// A peer in the WebRTC signaling room.
class SignalPeer {
  const SignalPeer({required this.peerId, required this.alias, required this.emoji});
  final String peerId;
  final String alias;
  final String emoji;
}

/// An incoming SDP/ICE relay from another peer.
class IncomingSignal {
  const IncomingSignal({required this.from, required this.kind, required this.payload});
  final String from;
  final String kind;
  final Map<String, dynamic> payload;
}

/// Signaling client for the browser-compatible WebRTC "nearby" room — the SAME
/// wire protocol the web uses (`/api/v1/nearby/ws?code=`): announce (`hello`),
/// track the peer roster, and relay SDP/ICE to a specific peer. Transport only;
/// the WebRTC lives in [WebrtcRoomService]. Lets the app join a room a web
/// browser hosts (and vice-versa once the app also advertises here).
class WebrtcSignaling {
  /// With [_code] the DO room is code-scoped (rooms); without it the server
  /// keys the room by caller public IP — the same "nearby" grouping the web
  /// transfer page uses, which is what lets the app appear in a browser's
  /// Nearby tab.
  WebrtcSignaling(this._self, [this._code]);

  final SignalPeer _self;
  final String? _code;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  void Function()? onOpen;
  void Function()? onClose;
  void Function(List<SignalPeer> peers)? onPeers;
  void Function(SignalPeer peer)? onPeerJoined;
  void Function(String peerId)? onPeerLeft;
  void Function(IncomingSignal signal)? onSignal;

  void connect() {
    if (_closed) return;
    final code = _code;
    final url =
        '${CloudConfig.wsBase}/api/v1/nearby/ws${code == null ? '' : '?code=${Uri.encodeComponent(code)}'}';
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _ws = channel;
      channel.sink.add(jsonEncode({
        'type': 'hello',
        'peerId': _self.peerId,
        'alias': _self.alias,
        'emoji': _self.emoji,
      }));
      onOpen?.call();
      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _handleClose(),
        onDone: _handleClose,
        cancelOnError: true,
      );
    } catch (_) {
      _handleClose();
    }
  }

  void _onMessage(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> m;
    try {
      m = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    String str(dynamic v) => v is String ? v : '';
    switch (m['type']) {
      case 'peers':
        final list = (m['peers'] as List? ?? [])
            .map((p) => SignalPeer(
                  peerId: str((p as Map)['peerId']),
                  alias: str(p['alias']),
                  emoji: str(p['emoji']),
                ))
            .where((p) => p.peerId.isNotEmpty)
            .toList();
        onPeers?.call(list);
        break;
      case 'peer_joined':
        onPeerJoined?.call(SignalPeer(
          peerId: str(m['peerId']),
          alias: str(m['alias']),
          emoji: str(m['emoji']),
        ));
        break;
      case 'peer_left':
        onPeerLeft?.call(str(m['peerId']));
        break;
      case 'signal':
        onSignal?.call(IncomingSignal(
          from: str(m['from']),
          kind: str(m['kind']),
          payload: (m['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        ));
        break;
      case 'full':
        _handleClose();
        break;
    }
  }

  /// Relay an SDP offer/answer or ICE candidate to exactly one peer.
  void signal(String to, String kind, Map<String, dynamic> payload) {
    try {
      _ws?.sink.add(jsonEncode({'type': 'signal', 'to': to, 'kind': kind, 'payload': payload}));
    } catch (_) {
      /* socket gone */
    }
  }

  void _handleClose() {
    _sub?.cancel();
    _sub = null;
    _ws = null;
    if (!_closed) onClose?.call();
  }

  void close() {
    _closed = true;
    try {
      _ws?.sink.add(jsonEncode({'type': 'bye'}));
    } catch (_) {
      /* already closing */
    }
    _sub?.cancel();
    _sub = null;
    try {
      _ws?.sink.close(ws_status.normalClosure);
    } catch (_) {
      /* noop */
    }
    _ws = null;
  }
}
