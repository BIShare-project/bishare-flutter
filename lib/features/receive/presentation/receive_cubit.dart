import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';

/// UI state for the receiver: a possible pending accept/reject prompt, a pending
/// file-request (reverse flow), and live receive progress.
class ReceiveState extends Equatable {
  const ReceiveState({
    this.pending,
    this.pendingRequest,
    this.progress,
    this.lastReceived,
    this.speed = 0,
  });

  final PendingTransfer? pending;
  final PendingFileRequest? pendingRequest;
  final ReceiveProgress? progress;
  final ReceivedFile? lastReceived;

  /// Live receive throughput in bytes/sec (0 until measurable). Mirrors the
  /// sender's live speed so the receive card shows the same "speed · ETA" line.
  final double speed;

  /// Estimated seconds remaining, derived from [speed] and the current progress.
  double? get etaSeconds {
    final p = progress;
    if (p == null || speed <= 0 || p.totalBytes <= p.bytesReceived) return null;
    return (p.totalBytes - p.bytesReceived) / speed;
  }

  ReceiveState copyWith({
    PendingTransfer? pending,
    PendingFileRequest? pendingRequest,
    ReceiveProgress? progress,
    ReceivedFile? lastReceived,
    double? speed,
    bool clearPending = false,
    bool clearRequest = false,
    bool clearProgress = false,
  }) => ReceiveState(
    pending: clearPending ? null : (pending ?? this.pending),
    pendingRequest: clearRequest ? null : (pendingRequest ?? this.pendingRequest),
    progress: clearProgress ? null : (progress ?? this.progress),
    lastReceived: lastReceived ?? this.lastReceived,
    speed: speed ?? this.speed,
  );

  @override
  List<Object?> get props => [
    pending?.id,
    pendingRequest?.id,
    progress?.bytesReceived,
    progress?.isComplete,
    lastReceived?.savedPath,
    speed,
  ];
}

/// Drives the accept/reject prompt, file-request prompt, and receive progress
/// from [TransferServer].
class ReceiveCubit extends Cubit<ReceiveState> {
  ReceiveCubit(this._server) : super(const ReceiveState()) {
    _incoming = _server.incoming.listen((p) {
      emit(state.copyWith(pending: p));
    });
    _incomingReq = _server.incomingRequests.listen((r) {
      emit(state.copyWith(pendingRequest: r));
    });
    _prog = _server.progress.listen((pr) {
      if (pr.isComplete) {
        // Record every session that reaches a terminal state — even one whose
        // clear is skipped just below — so ANY later straggler for it (terminal
        // OR live) is recognised as belonging to a finished transfer.
        _markSessionEnded(pr.sessionId);
        // Ignore a terminal event for a session that isn't the one on screen — a
        // straggler QUIC Error (control + up to S data streams each emit one,
        // seconds apart) for an old/cancelled session must not clobber a newer
        // session's live card.
        final current = state.progress?.sessionId ?? _swSession;
        if (current != null && current != pr.sessionId) return;
        _sw
          ..stop()
          ..reset();
        _swSession = null;
        emit(state.copyWith(clearProgress: true, speed: 0));
        return;
      }
      // Safety net: a LIVE (non-terminal) progress event for a session that has
      // already finished must never RESURRECT the card. The server drops a
      // session the instant it completes/cancels/errors, so no terminal would
      // ever follow such a straggler — without this guard it re-shows the
      // floating receive card and wedges it at a stale percentage until the app
      // is restarted (the reported "stuck receive card" bug; the idle reaper
      // can't recover it because the session is already gone). Terminal
      // stragglers are handled above; this covers the non-terminal ones that the
      // sessionId guard alone lets through.
      if (_endedSessions.contains(pr.sessionId)) return;
      // Restart the clock on a new transfer so speed/ETA measure THIS one.
      if (_swSession != pr.sessionId) {
        _swSession = pr.sessionId;
        _sw
          ..reset()
          ..start();
      }
      final secs = _sw.elapsedMilliseconds / 1000;
      final speed = secs > 0.2 ? pr.bytesReceived / secs : state.speed;
      emit(state.copyWith(progress: pr, speed: speed));
    });
    _recv = _server.received.listen((f) {
      emit(state.copyWith(lastReceived: f));
    });
  }

  final TransferServer _server;
  // Live-speed clock for the receive card (mirrors send_cubit's `_sw`), keyed by
  // session so a new transfer restarts the measurement.
  final _sw = Stopwatch();
  String? _swSession;

  /// Sessions that have reached a terminal state, kept as a small bounded set
  /// (sessionIds are v4 UUIDs, so this never false-matches a fresh transfer).
  /// Used to drop late stragglers so a finished transfer can neither resurrect
  /// nor clobber the floating receive card. See the progress listener.
  final _endedSessions = <String>{};
  final _endedOrder = <String>[];

  void _markSessionEnded(String sessionId) {
    if (_endedSessions.add(sessionId)) {
      _endedOrder.add(sessionId);
      if (_endedOrder.length > 64) {
        _endedSessions.remove(_endedOrder.removeAt(0));
      }
    }
  }

  late final StreamSubscription<PendingTransfer> _incoming;
  late final StreamSubscription<PendingFileRequest> _incomingReq;
  late final StreamSubscription<ReceiveProgress> _prog;
  late final StreamSubscription<ReceivedFile> _recv;

  void accept() {
    state.pending?.accept();
    emit(state.copyWith(clearPending: true));
  }

  void reject() {
    state.pending?.reject();
    emit(state.copyWith(clearPending: true));
  }

  /// Clear the surfaced file-request once its sheet has taken ownership.
  void clearRequest() => emit(state.copyWith(clearRequest: true));

  @override
  Future<void> close() async {
    await _incoming.cancel();
    await _incomingReq.cancel();
    await _prog.cancel();
    await _recv.cancel();
    return super.close();
  }
}
