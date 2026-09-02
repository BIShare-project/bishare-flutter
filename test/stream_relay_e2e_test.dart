import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/server/transfer_types.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/remote/data/binary_frame.dart';
import 'package:bishare/features/remote/data/cloud_transfer_service.dart';
import 'package:bishare/features/remote/data/stream_relay_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/rust_test_lib.dart';

class _FakeServer extends Mock implements TransferServer {}

class _FakeHistory extends Mock implements HistoryRepository {}

/// mocktail needs a registered fallback to accept `any()` for this type.
class _FakeReceivedFile extends Fake implements ReceivedFile {}

/// The production StreamDO's observable behaviour, in-process: pair by code,
/// transform accept/reject, forward everything else raw, orphan on close.
/// Instrumented to measure what a real relay would have to buffer: bytes the
/// sender has pushed minus bytes the receiver has acknowledged.
class _MockRelay {
  _MockRelay(this.server);
  final HttpServer server;
  final Map<String, _Session> byCode = {};

  /// Artificial delay before each binary frame reaches the receiver — a slow
  /// receiver, without which acks would keep up and prove nothing.
  Duration receiverDelay = Duration.zero;

  /// Every byte the sender pushed (frame headers included).
  int senderBytes = 0;
  int lastAck = 0;
  int maxOutstanding = 0;
  bool sawPlaintextMarker = false;
  final List<String> receiverTexts = [];
  Uint8List? firstDataPayload;

  Uri get uri =>
      Uri.parse('ws://${server.address.address}:${server.port}/api/v1/stream');

  static Future<_MockRelay> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _MockRelay(s);
    s.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      relay._handle(ws);
    });
    return relay;
  }

  void _handle(WebSocket ws) {
    _Session? session;
    String? role;
    Future<void> queue = Future.value(); // keeps delayed forwards in order
    ws.listen(
      (msg) {
        if (session == null) {
          final m = jsonDecode(msg as String) as Map<String, dynamic>;
          final data = (m['data'] as Map?)?.cast<String, dynamic>() ?? {};
          if (m['type'] == 'create') {
            final code = 'C${byCode.length}TEST'
                .padRight(6, 'X')
                .substring(0, 6);
            session = _Session(code, ws, data);
            role = 'sender';
            byCode[code] = session!;
            ws.add(
              jsonEncode({
                'type': 'created',
                'data': {'code': code, 'sessionId': 's'},
              }),
            );
          } else if (m['type'] == 'join') {
            final s = byCode[(data['code'] as String).toUpperCase()];
            if (s == null) {
              ws.add(
                jsonEncode({
                  'type': 'error',
                  'data': {'message': 'session not found'},
                }),
              );
              ws.close();
              return;
            }
            session = s..receiver = ws;
            role = 'receiver';
            s.sender.add(
              jsonEncode({
                'type': 'joined',
                'data': {'alias': 'receiver', 'deviceType': 'mobile'},
              }),
            );
            ws.add(jsonEncode({'type': 'file-info', 'data': s.fileInfo}));
          }
          return;
        }
        final peer = role == 'sender' ? session!.receiver : session!.sender;
        if (msg is! String) {
          final bytes = msg as List<int>;
          if (role == 'sender') {
            senderBytes += bytes.length;
            maxOutstanding = max(maxOutstanding, senderBytes - lastAck);
            final u = Uint8List.fromList(bytes);
            if (firstDataPayload == null &&
                u.isNotEmpty &&
                u[0] == FrameType.fileData) {
              firstDataPayload = u.sublist(9);
            }
            if (!sawPlaintextMarker &&
                utf8
                    .decode(bytes, allowMalformed: true)
                    .contains('BISHARE-PLAINTEXT-MARKER')) {
              sawPlaintextMarker = true;
            }
            queue = queue.then((_) async {
              if (receiverDelay > Duration.zero) {
                await Future<void>.delayed(receiverDelay);
              }
              peer?.add(bytes);
            });
          } else {
            peer?.add(bytes);
          }
          return;
        }
        final type = (jsonDecode(msg) as Map)['type'];
        if (role == 'receiver') {
          receiverTexts.add(type as String);
          if (type == 'accept') {
            session!.sender.add(jsonEncode({'type': 'accepted'}));
            return;
          }
          if (type == 'ack') {
            lastAck =
                ((jsonDecode(msg) as Map)['data'] as Map)['received'] as int;
          }
        }
        peer?.add(msg); // hello, ack, cancel … forwarded raw
      },
      onDone: () {
        final peer = role == 'sender' ? session?.receiver : session?.sender;
        try {
          peer?.add(jsonEncode({'type': 'peer-left'}));
        } on Object {
          // peer gone
        }
      },
    );
  }

  Future<void> close() => server.close(force: true);
}

class _Session {
  _Session(this.code, this.sender, this.fileInfo);
  final String code;
  final WebSocket sender;
  final Map<String, dynamic> fileInfo;
  WebSocket? receiver;
}

/// What a 2.4.5 app does on the receiving side: join, accept, save the bytes.
/// No hello, no acks.
Future<List<int>> legacyReceive(Uri relay, String code) async {
  final ws = await WebSocket.connect(relay.toString());
  final out = <int>[];
  final done = Completer<void>();
  final decoder = FrameDecoder();
  ws.listen(
    (msg) {
      if (msg is String) {
        final m = jsonDecode(msg) as Map;
        if (m['type'] == 'file-info') ws.add(jsonEncode({'type': 'accept'}));
        if (m['type'] == 'peer-left' && !done.isCompleted) done.complete();
        return;
      }
      for (final f in decoder.add(Uint8List.fromList(msg as List<int>))) {
        if (f.type == FrameType.fileData) out.addAll(f.payload);
        if (f.type == FrameType.sessionEnd && !done.isCompleted) {
          done.complete();
        }
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  ws.add(
    jsonEncode({
      'type': 'join',
      'data': {'code': code},
    }),
  );
  await done.future.timeout(const Duration(seconds: 30));
  await ws.close();
  return out;
}

void main() {
  late bool rust;
  late Directory tmp;
  late Directory saveDir;
  late _MockRelay relay;
  late StreamRelayService sender;
  late StreamRelayService receiver;

  setUpAll(() async {
    rust = await initRustForTests();
    registerFallbackValue(_FakeReceivedFile());
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('stream-relay-test');
    saveDir = Directory('${tmp.path}/inbox')..createSync();
    relay = await _MockRelay.start();
    final server = _FakeServer();
    when(() => server.saveDirectory).thenReturn(saveDir);
    final history = _FakeHistory();
    when(() => history.recordReceived(any())).thenAnswer((_) async {});
    sender = StreamRelayService(server, history, wsUri: relay.uri);
    receiver = StreamRelayService(server, history, wsUri: relay.uri);
  });

  tearDown(() async {
    await relay.close();
    await tmp.delete(recursive: true);
  });

  Future<File> plain(int size) async {
    final r = Random(5);
    final bytes = List<int>.generate(size, (_) => r.nextInt(256));
    // A marker the relay can search for: if it ever sees this, bytes were plaintext.
    bytes.setRange(1000, 1000 + 24, utf8.encode('BISHARE-PLAINTEXT-MARKER'));
    final f = File('${tmp.path}/clip.mp4');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  /// Drive `send` and hand back the code/key once the QR would be shown,
  /// leaving the rest of the events to collect in the background.
  Future<({String code, String? key, Future<List<StreamSendEvent>> events})>
  startSend(File file, {required bool encrypt}) async {
    final events = <StreamSendEvent>[];
    final ready = Completer<({String code, String? key})>();
    final done = Completer<List<StreamSendEvent>>();
    sender
        .send(
          file,
          fileName: 'clip.mp4',
          mimeType: 'video/mp4',
          senderAlias: 'Nima',
          encrypt: encrypt,
        )
        .listen((e) {
          events.add(e);
          if (e is StreamCodeReady && !ready.isCompleted) {
            ready.complete((code: e.code, key: e.key));
          }
        }, onDone: () => done.complete(events));
    final r = await ready.future.timeout(const Duration(seconds: 30));
    return (code: r.code, key: r.key, events: done.future);
  }

  test(
    'a sealed live transfer round-trips and the relay only ever sees ciphertext',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final file = await plain(3 * 1024 * 1024 + 321);
      final s = await startSend(file, encrypt: true);
      expect(s.key, isNotNull);
      expect(s.key, hasLength(43));

      final got = await receiver.receive(s.code, key: s.key);
      final events = await s.events;

      expect(events.last, isA<StreamSendComplete>());
      expect(events.whereType<StreamReceiverJoined>(), hasLength(1));
      expect(await File(got.savedPath).readAsBytes(), await file.readAsBytes());
      expect(
        got.verified,
        isTrue,
        reason: 'every record authenticated by its GCM tag',
      );
      expect(got.fileName, 'clip.mp4');
      expect(
        saveDir.listSync().map((e) => e.path.split('/').last),
        ['clip.mp4'],
        reason: 'no ciphertext scratch left beside the file',
      );

      // The wire carried a BSE2 container, never the file.
      expect(relay.firstDataPayload!.sublist(0, 4), Bse2.magic);
      expect(relay.sawPlaintextMarker, isFalse);
      expect(relay.receiverTexts.first, 'accept');
      expect(relay.receiverTexts[1], 'hello');
      expect(
        relay.lastAck,
        Bse2.ciphertextSize(await file.length()),
        reason:
            'sender completes only after the receiver acknowledged everything',
      );
    },
  );

  test(
    'a hand-typed code has no key: the sealed session is refused, nothing is saved',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final file = await plain(200 * 1024);
      final s = await startSend(file, encrypt: true);

      await expectLater(
        receiver.receive(s.code),
        throwsA(
          isA<CloudDownloadException>().having(
            (e) => e.message,
            'message',
            'remote.encrypted_needs_link',
          ),
        ),
      );
      expect(
        saveDir.listSync(),
        isEmpty,
        reason: 'the reserved target must be removed',
      );
    },
  );

  test(
    'a previous-version receiver: sealed send stops with the update message; plain send still works',
    () async {
      final file = await plain(300 * 1024);

      if (rust) {
        final s = await startSend(file, encrypt: true);
        final legacy = legacyReceive(relay.uri, s.code);
        final events = await s.events;
        expect(events.last, isA<StreamSendFailed>());
        expect(
          (events.last as StreamSendFailed).message,
          'remote.live_receiver_needs_update',
        );
        expect(
          events.whereType<StreamReceiverJoined>(),
          isEmpty,
          reason: 'stopped before any byte was sent',
        );
        await legacy.catchError((_) => <int>[]);
      }

      final s2 = await startSend(file, encrypt: false);
      final bytes = await legacyReceive(relay.uri, s2.code);
      final events2 = await s2.events;
      expect(events2.last, isA<StreamSendComplete>());
      expect(bytes, await file.readAsBytes());
    },
  );

  test(
    'a slow receiver never gets more than the window ahead of its acks',
    () async {
      final file = await plain(24 * 1024 * 1024);
      relay.receiverDelay = const Duration(
        milliseconds: 3,
      ); // ~0.4 MiB/s of 64 KiB frames
      final s = await startSend(file, encrypt: false);

      ReceivedFile got;
      try {
        got = await receiver.receive(s.code);
      } on Object catch (e) {
        final ev = await s.events.timeout(
          const Duration(seconds: 5),
          onTimeout: () => [],
        );
        final last = ev.isNotEmpty ? ev.last : null;
        fail(
          'receive failed: $e | sender: ${ev.map((x) => x.runtimeType).join(",")}'
          '${last is StreamSendFailed ? " → ${last.message}" : ""}'
          ' | relay senderBytes=${relay.senderBytes} lastAck=${relay.lastAck} '
          'maxOutstanding=${relay.maxOutstanding}',
        );
      }
      final events = await s.events;

      expect(events.last, isA<StreamSendComplete>());
      expect(await File(got.savedPath).length(), await file.length());
      // Frame headers (9 bytes per 64 KiB) are counted on the sender side but not
      // in acks, so allow one window's worth of headers plus one chunk.
      const slack =
          64 * 1024 + (StreamRelayService.ackWindow ~/ (64 * 1024)) * 9;
      expect(
        relay.maxOutstanding,
        lessThanOrEqualTo(StreamRelayService.ackWindow + slack),
        reason: 'the sender must pause when the receiver falls behind',
      );
      expect(
        relay.maxOutstanding,
        greaterThan(StreamRelayService.ackWindow ~/ 2),
        reason: 'the window was actually exercised (receiver was slow)',
      );
    },
  );
}
