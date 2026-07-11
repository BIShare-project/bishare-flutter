import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../constants/cloud.dart';

/// Lifecycle of the relay socket, surfaced so features can render presence /
/// retry affordances without owning the socket themselves.
enum RelayConnectionState { connecting, connected, reconnecting, closed }

/// Opens the WebSocket — injectable so tests can substitute a fake channel.
typedef RelayWebSocketConnector = WebSocketChannel Function(Uri uri);

/// One WS+REST abstraction over the cloud relay ([CloudConfig.apiBase]),
/// unifying the connection handling that `StreamRelayService`, `RoomService`
/// and `CloudTransferService` each grew separately. A single socket carries
/// typed sub-channels multiplexed by a JSON envelope
/// `{channel: "signaling"|"broadcast"|"sync", payload: {…}}` — see
/// [signaling], [broadcast] and [sync]. This class stays free of feature
/// logic; features (clipboard relay, WebRTC signaling, broadcast control,
/// folder sync) attach to a lane in later waves.
///
/// Reconnects automatically (3s doubling to a ~30s cap, plus jitter — the
/// existing services' 3s retry, hardened for fleets) until [close] is called.
class RelayChannelClient {
  RelayChannelClient({Dio? dio, RelayWebSocketConnector? connectWebSocket})
    : _dio = dio ?? Dio(BaseOptions(receiveTimeout: Duration.zero)),
      _connectWebSocket = connectWebSocket ?? WebSocketChannel.connect;

  final Dio _dio;
  final RelayWebSocketConnector _connectWebSocket;
  final Random _random = Random();

  /// Relay-channel WebSocket path. Full URL: [CloudConfig.wsBase] + this.
  /// (Kept here rather than in [CloudConfig] until the backing Worker ships.)
  static String channelWs(String channelId) => '/api/v1/channel/$channelId/ws';

  /// The lane names the envelope may address; anything else is dropped.
  static const Set<String> _lanes = {'signaling', 'broadcast', 'sync'};

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  String? _channelId;
  bool _active = false;
  int _attempt = 0;

  /// Incoming payload streams per lane, keyed by the envelope's `channel`.
  final Map<String, StreamController<Map<String, dynamic>>> _incoming = {};

  RelayConnectionState _state = RelayConnectionState.closed;
  final StreamController<RelayConnectionState> _states =
      StreamController<RelayConnectionState>.broadcast();

  /// The current lifecycle state (see [states] for transitions).
  RelayConnectionState get state => _state;

  /// Lifecycle transitions of the relay socket.
  Stream<RelayConnectionState> get states => _states.stream;

  /// WebRTC offer/answer/ICE signaling lane (screen share, remote camera).
  late final SignalingChannel signaling = SignalingChannel._(this);

  /// Broadcast-send control lane (multi-receiver orchestration).
  late final BroadcastControlChannel broadcast = BroadcastControlChannel._(
    this,
  );

  /// Sync lane (clipboard relay, folder-sync manifest deltas).
  late final SyncChannel sync = SyncChannel._(this);

  /// Open the relay socket for [channelId] (e.g. a per-account channel) and
  /// keep it alive until [close]. Calling again switches channels.
  void connect(String channelId) {
    _channelId = channelId;
    _active = true;
    _attempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(RelayConnectionState.connecting);
    _openSocket();
  }

  /// Stop reconnecting and drop the socket. The client stays reusable — a
  /// later [connect] starts a fresh session on the same sub-channel streams.
  Future<void> close() async {
    _active = false;
    _channelId = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // Capture + null the socket state SYNCHRONOUSLY (before any await): a
    // connect() racing in during the awaits below must find clean fields and
    // keep its own fresh socket/subscription untouched.
    final sub = _wsSub;
    final ws = _ws;
    _wsSub = null;
    _ws = null;
    await sub?.cancel();
    if (ws != null) {
      try {
        // Never block on this: sink.close() of a socket whose handshake is
        // still in flight can hang until the handshake resolves (or forever
        // when the relay is unreachable). Fire-and-forget is safe — the
        // subscription is already cancelled, so no callback can fire.
        unawaited(
          ws.sink.close(ws_status.normalClosure).catchError((Object _) {}),
        );
      } on Object {
        // already closed
      }
    }
    // A connect() may have raced in while we awaited — keep its state then.
    if (!_active) _setState(RelayConnectionState.closed);
  }

  void _openSocket() {
    if (!_active || _channelId == null) return;
    // Tear down any prior socket so reconnects don't stack subscriptions.
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close(ws_status.normalClosure);
    _ws = null;
    try {
      final channel = _connectWebSocket(
        Uri.parse('${CloudConfig.wsBase}${channelWs(_channelId!)}'),
      );
      _ws = channel;
      channel.ready
          .then((_) {
            // A newer socket may have replaced this one while we handshook.
            if (!identical(_ws, channel)) return;
            _attempt = 0;
            _setState(RelayConnectionState.connected);
          })
          .catchError((Object _) {
            // Connect failures surface on the stream too; onError reconnects.
          });
      _wsSub = channel.stream.listen(
        _onMessage,
        onDone: _onSocketClosed,
        onError: (Object _) => _onSocketClosed(),
        cancelOnError: true,
      );
    } on Object {
      _onSocketClosed();
    }
  }

  void _onSocketClosed() {
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    if (!_active) return;
    _setState(RelayConnectionState.reconnecting);
    // 3s doubling to a 30s cap, plus 0–1s jitter so a fleet of clients that
    // lost the same relay doesn't reconnect in lockstep.
    final seconds = min(3 << min(_attempt, 4), 30);
    _attempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: seconds, milliseconds: _random.nextInt(1000)),
      _openSocket,
    );
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on Object {
      return;
    }
    final name = msg['channel'];
    if (name is! String || !_lanes.contains(name)) return;
    final payload = msg['payload'];
    _lane(name).add(
      payload is Map ? payload.cast<String, dynamic>() : <String, dynamic>{},
    );
  }

  StreamController<Map<String, dynamic>> _lane(String name) => _incoming
      .putIfAbsent(name, StreamController<Map<String, dynamic>>.broadcast);

  void _sendEnvelope(String channel, Map<String, dynamic> payload) {
    final ws = _ws;
    if (ws == null) {
      throw StateError('Relay channel is not connected (call connect first)');
    }
    ws.sink.add(jsonEncode({'channel': channel, 'payload': payload}));
  }

  void _setState(RelayConnectionState next) {
    if (next == _state) return;
    _state = next;
    _states.add(next);
  }

  // ---- REST (same relay host; non-realtime calls) ----

  Uri _api(String path) => Uri.parse('${CloudConfig.apiBase}$path');

  /// GET [path] (relative to the relay API base) and unwrap the body.
  Future<Map<String, dynamic>?> getJson(
    String path, {
    Map<String, String>? query,
    CancelToken? cancel,
  }) async {
    var uri = _api(path);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: query);
    }
    final res = await _dio.getUri<Map<String, dynamic>>(
      uri,
      cancelToken: cancel,
    );
    return _data(res);
  }

  /// POST [data] to [path] and unwrap the body.
  Future<Map<String, dynamic>?> postJson(
    String path, {
    Object? data,
    Options? options,
    CancelToken? cancel,
  }) async {
    final res = await _dio.postUri<Map<String, dynamic>>(
      _api(path),
      data: data,
      options: options,
      cancelToken: cancel,
    );
    return _data(res);
  }

  /// DELETE [path] (revoking relay resources) and unwrap the body.
  Future<Map<String, dynamic>?> deleteJson(
    String path, {
    Options? options,
    CancelToken? cancel,
  }) async {
    final res = await _dio.deleteUri<Map<String, dynamic>>(
      _api(path),
      options: options,
      cancelToken: cancel,
    );
    return _data(res);
  }

  /// Unwraps the `{success, data}` envelope; tolerates flat bodies.
  Map<String, dynamic>? _data(Response<Map<String, dynamic>> res) {
    final body = res.data;
    if (body == null) return null;
    final inner = body['data'];
    if (inner is Map<String, dynamic>) return inner;
    return body;
  }
}

/// One typed lane multiplexed over the relay socket by the envelope's
/// `channel` field. Deliberately thin — payload semantics belong to the
/// features that attach in later waves.
abstract class RelaySubChannel {
  RelaySubChannel._(this._client, this._name);

  final RelayChannelClient _client;
  final String _name;

  /// Decoded `payload` objects addressed to this lane.
  Stream<Map<String, dynamic>> get incoming => _client._lane(_name).stream;

  /// Wrap [payload] in the envelope and write it to the socket.
  void send(Map<String, dynamic> payload) =>
      _client._sendEnvelope(_name, payload);
}

/// WebRTC offer/answer/ICE signaling (screen mirroring, remote camera).
class SignalingChannel extends RelaySubChannel {
  SignalingChannel._(RelayChannelClient client) : super._(client, 'signaling');
}

/// Broadcast-send control messages (multi-receiver orchestration).
class BroadcastControlChannel extends RelaySubChannel {
  BroadcastControlChannel._(RelayChannelClient client)
    : super._(client, 'broadcast');
}

/// Sync payloads (clipboard relay, folder-sync manifest deltas).
class SyncChannel extends RelaySubChannel {
  SyncChannel._(RelayChannelClient client) : super._(client, 'sync');
}
