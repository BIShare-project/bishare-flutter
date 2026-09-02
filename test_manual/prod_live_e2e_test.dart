// MANUAL end-to-end check of Live mode against the PRODUCTION relay
// (wss://api.bishare.app/api/v1/stream). Lives outside test/ so CI never
// touches the live relay.
//
//   cargo build --manifest-path rust/Cargo.toml
//   flutter test test_manual/prod_live_e2e_test.dart
//
// Runs the real sender and the real receiver code paths — the same ones the
// app uses — through the real StreamDO: the file is sealed, the key rides only
// in the QR payload, the relay forwards ciphertext, the receiver opens it.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:bishare/core/deeplink/deep_link.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/server/transfer_types.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/remote/data/stream_relay_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test/helpers/rust_test_lib.dart';

class _FakeServer extends Mock implements TransferServer {}

class _FakeHistory extends Mock implements HistoryRepository {}

class _FakeReceivedFile extends Fake implements ReceivedFile {}

void main() {
  test('PROD relay: sealed Live transfer, key only in the QR, receiver opens it', () async {
    expect(await initRustForTests(), isTrue, reason: 'build the native lib first');
    registerFallbackValue(_FakeReceivedFile());
    final tmp = await Directory.systemTemp.createTemp('bishare-prod-live-');
    final inbox = Directory('${tmp.path}/inbox')..createSync();
    final server = _FakeServer();
    when(() => server.saveDirectory).thenReturn(inbox);
    final history = _FakeHistory();
    when(() => history.recordReceived(any())).thenAnswer((_) async {});

    final size = int.tryParse(Platform.environment['E2E_SIZE'] ?? '') ?? 3 * 1024 * 1024 + 777;
    final r = Random.secure();
    final src = File('${tmp.path}/clip.bin')
      ..writeAsBytesSync(List<int>.generate(size, (_) => r.nextInt(256)));

    final sender = StreamRelayService(server, history);
    final receiver = StreamRelayService(server, history);

    final ready = Completer<StreamCodeReady>();
    final events = <StreamSendEvent>[];
    final done = Completer<void>();
    sender
        .send(src, fileName: 'clip.bin', mimeType: 'application/octet-stream', senderAlias: 'e2e')
        .listen((e) {
          events.add(e);
          if (e is StreamCodeReady && !ready.isCompleted) ready.complete(e);
        }, onDone: done.complete);

    final code = await ready.future.timeout(const Duration(seconds: 30));
    // Exactly what the sender's QR carries — and what the receiver scans.
    final qr = 'bishare-stream://${code.code}#k=${code.key}';
    stdout.writeln('qr: bishare-stream://${code.code}#k=…');
    final link = DeepLink.parse(qr)! as StreamReceiveLink;
    expect(link.key, code.key, reason: 'the key survives the QR round trip');

    final t0 = DateTime.now();
    final got = await receiver.receive(link.code, key: link.key);
    await done.future.timeout(const Duration(seconds: 30));

    expect(events.last, isA<StreamSendComplete>(), reason: '${events.last}');
    expect(await File(got.savedPath).readAsBytes(), await src.readAsBytes());
    expect(got.verified, isTrue);
    expect(Bse2.decodeKey(code.key!), isNotNull);
    stdout.writeln(
      'ok — $size bytes sealed through the production relay in '
      '${DateTime.now().difference(t0).inMilliseconds} ms; receiver file matches',
    );
    await tmp.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
