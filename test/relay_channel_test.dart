import 'dart:async';
import 'dart:convert';

import 'package:bishare/core/relay/relay_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Validates the relay-channel client against a fake socket: the JSON envelope
/// `{channel, payload}` routes to the right typed sub-channel, sends are
/// wrapped in the same envelope, and the connection-state stream walks
/// connecting → connected → reconnecting → closed.
void main() {
  test('routes envelopes to the matching sub-channel', () async {
    final socket = _FakeSocket();
    final client = RelayChannelClient(connectWebSocket: (_) => socket);
    final signaling = <Map<String, dynamic>>[];
    final sync = <Map<String, dynamic>>[];
    client.signaling.incoming.listen(signaling.add);
    client.sync.incoming.listen(sync.add);
    client.connect('acct-1');
    await pumpEventQueue();

    socket.fromServer.add(
      jsonEncode({
        'channel': 'signaling',
        'payload': {'sdp': 'offer'},
      }),
    );
    socket.fromServer.add(
      jsonEncode({
        'channel': 'sync',
        'payload': {'rev': 3},
      }),
    );
    // Garbage / unknown lanes are dropped, never crash the socket.
    socket.fromServer.add('not json');
    socket.fromServer.add(
      jsonEncode({'channel': 'bogus', 'payload': <String, dynamic>{}}),
    );
    await pumpEventQueue();

    expect(signaling, [
      {'sdp': 'offer'},
    ]);
    expect(sync, [
      {'rev': 3},
    ]);
    await client.close();
  });

  test('send wraps the payload in the envelope', () async {
    final socket = _FakeSocket();
    final client = RelayChannelClient(connectWebSocket: (_) => socket);
    client.connect('acct-1');
    await pumpEventQueue();

    client.broadcast.send({'op': 'start', 'receivers': 2});

    expect(socket.sent, [
      jsonEncode({
        'channel': 'broadcast',
        'payload': {'op': 'start', 'receivers': 2},
      }),
    ]);
    await client.close();
  });

  test('send before connect throws', () {
    final client = RelayChannelClient(connectWebSocket: (_) => _FakeSocket());
    expect(() => client.sync.send({'a': 1}), throwsStateError);
  });

  test('states: connecting → connected → reconnecting → closed', () async {
    final sockets = <_FakeSocket>[];
    final client = RelayChannelClient(
      connectWebSocket: (_) {
        final s = _FakeSocket();
        sockets.add(s);
        return s;
      },
    );
    final states = <RelayConnectionState>[];
    client.states.listen(states.add);

    client.connect('acct-1');
    await pumpEventQueue();
    expect(states, [
      RelayConnectionState.connecting,
      RelayConnectionState.connected,
    ]);

    // The relay dropped us — the client schedules a retry (3s + jitter).
    await sockets.single.fromServer.close();
    await pumpEventQueue();
    expect(client.state, RelayConnectionState.reconnecting);

    // close() cancels the pending retry and lands in closed.
    await client.close();
    expect(client.state, RelayConnectionState.closed);
    expect(sockets, hasLength(1));
  });
}

/// Fake relay socket: records what the client wrote and lets the test inject
/// server frames or a disconnect. Only the members [RelayChannelClient]
/// touches are implemented; [noSuchMethod] covers the rest of the
/// StreamChannel surface.
class _FakeSocket implements WebSocketChannel {
  final StreamController<dynamic> fromServer = StreamController<dynamic>();
  final List<dynamic> sent = <dynamic>[];

  @override
  Stream<dynamic> get stream => fromServer.stream;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._socket);
  final _FakeSocket _socket;

  @override
  void add(dynamic data) => _socket.sent.add(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_socket.fromServer.isClosed) await _socket.fromServer.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
