import 'dart:async';

import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/server/transfer_types.dart';
import 'package:bishare/features/receive/presentation/receive_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in for [TransferServer] that exposes only the four streams
/// [ReceiveCubit] subscribes to, so the receive-card lifecycle can be driven
/// with exact server event sequences (no HTTP server / Rust FFI needed).
class _FakeServer implements TransferServer {
  final progressCtrl = StreamController<ReceiveProgress>.broadcast();
  final incomingCtrl = StreamController<PendingTransfer>.broadcast();
  final incomingReqCtrl = StreamController<PendingFileRequest>.broadcast();
  final receivedCtrl = StreamController<ReceivedFile>.broadcast();

  @override
  Stream<ReceiveProgress> get progress => progressCtrl.stream;
  @override
  Stream<PendingTransfer> get incoming => incomingCtrl.stream;
  @override
  Stream<PendingFileRequest> get incomingRequests => incomingReqCtrl.stream;
  @override
  Stream<ReceivedFile> get received => receivedCtrl.stream;

  Future<void> disposeCtrls() => Future.wait([
    progressCtrl.close(),
    incomingCtrl.close(),
    incomingReqCtrl.close(),
    receivedCtrl.close(),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ReceiveProgress _p(
  String sessionId, {
  required int bytes,
  int total = 100,
  bool complete = false,
}) => ReceiveProgress(
  sessionId: sessionId,
  senderAlias: 'iPhone',
  totalFiles: 1,
  completedFiles: complete ? 1 : 0,
  currentFileName: 'photo.jpg',
  bytesReceived: bytes,
  totalBytes: total,
  isComplete: complete,
);

/// Broadcast delivery is async — let the microtask/event queue drain.
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeServer server;
  late ReceiveCubit cubit;

  setUp(() {
    server = _FakeServer();
    cubit = ReceiveCubit(server);
  });

  tearDown(() async {
    await cubit.close();
    await server.disposeCtrls();
  });

  test('a clean transfer shows then clears the receive card', () async {
    server.progressCtrl.add(_p('S1', bytes: 0)); // prepare
    await _tick();
    server.progressCtrl.add(_p('S1', bytes: 60)); // streaming
    await _tick();
    expect(cubit.state.progress, isNotNull);

    server.progressCtrl.add(_p('S1', bytes: 100, complete: true)); // done
    await _tick();
    expect(cubit.state.progress, isNull, reason: 'terminal must clear the card');
  });

  test(
    'a late non-terminal straggler cannot resurrect a finished card '
    '(the stuck receive-card bug)',
    () async {
      server.progressCtrl.add(_p('S1', bytes: 0));
      await _tick();
      server.progressCtrl.add(_p('S1', bytes: 100, complete: true));
      await _tick();
      expect(cubit.state.progress, isNull);

      // Server dropped S1 on completion; a delayed live-progress straggler for
      // it must be ignored (no terminal would ever follow → would hang forever).
      server.progressCtrl.add(_p('S1', bytes: 40));
      await _tick();
      expect(
        cubit.state.progress,
        isNull,
        reason: 'a finished session must not re-show the card',
      );
    },
  );

  test('a terminal for the shown session always clears it', () async {
    server.progressCtrl.add(_p('S1', bytes: 0));
    await _tick();
    server.progressCtrl.add(_p('S1', bytes: 50));
    await _tick();
    // Idle reaper emits a terminal with bytes 0 for the shown session.
    server.progressCtrl.add(_p('S1', bytes: 0, complete: true));
    await _tick();
    expect(cubit.state.progress, isNull);
  });

  test('an old straggler does not clobber a newer live card', () async {
    server.progressCtrl.add(_p('OLD', bytes: 50));
    await _tick();
    // A newer session becomes the live card.
    server.progressCtrl.add(_p('NEW', bytes: 0, total: 200));
    await _tick();
    expect(cubit.state.progress?.sessionId, 'NEW');

    // A straggler TERMINAL for the old session must not clear the new card...
    server.progressCtrl.add(_p('OLD', bytes: 0, complete: true));
    await _tick();
    expect(cubit.state.progress?.sessionId, 'NEW');

    // ...and neither may a straggler LIVE event for the old session.
    server.progressCtrl.add(_p('OLD', bytes: 70));
    await _tick();
    expect(cubit.state.progress?.sessionId, 'NEW');

    // The new session still completes cleanly.
    server.progressCtrl.add(_p('NEW', bytes: 200, complete: true));
    await _tick();
    expect(cubit.state.progress, isNull);
  });
}
