import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/telemetry/telemetry_service.dart';
import '../../../core/review/review_prompter.dart';

/// How a receive ended, for the card that stays a few seconds after it: all
/// files saved, or stopped part way (the sender cancelled, or vanished).
class ReceiveOutcome {
  const ReceiveOutcome({
    required this.sessionId,
    required this.senderAlias,
    required this.saved,
    required this.total,
    required this.bytes,
  });

  final String sessionId;
  final String senderAlias;
  final int saved;
  final int total;

  /// The size of the whole offer.
  final int bytes;

  bool get complete => saved >= total;
}

/// UI state for the receiver: a possible pending accept/reject prompt, a pending
/// file-request (reverse flow), and live receive progress.
class ReceiveState extends Equatable {
  const ReceiveState({
    this.pending,
    this.pendingRequest,
    this.progress,
    this.lastReceived,
    this.outcome,
    this.speed = 0,
  });

  final PendingTransfer? pending;
  final PendingFileRequest? pendingRequest;
  final ReceiveProgress? progress;
  final ReceivedFile? lastReceived;

  /// The last receive that ended (null until one does).
  final ReceiveOutcome? outcome;

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
    ReceiveOutcome? outcome,
    double? speed,
    bool clearPending = false,
    bool clearRequest = false,
    bool clearProgress = false,
  }) => ReceiveState(
    pending: clearPending ? null : (pending ?? this.pending),
    pendingRequest: clearRequest
        ? null
        : (pendingRequest ?? this.pendingRequest),
    progress: clearProgress ? null : (progress ?? this.progress),
    lastReceived: lastReceived ?? this.lastReceived,
    outcome: outcome ?? this.outcome,
    speed: speed ?? this.speed,
  );

  @override
  List<Object?> get props => [
    pending?.id,
    pendingRequest?.id,
    progress?.bytesReceived,
    progress?.isComplete,
    lastReceived?.savedPath,
    outcome?.sessionId,
    speed,
  ];
}

/// Drives the accept/reject prompt, file-request prompt, and receive progress
/// from [TransferServer].
class ReceiveCubit extends Cubit<ReceiveState> {
  ReceiveCubit(this._server, this._telemetry, {ReviewPrompter? review})
    : _review = review,
      super(const ReceiveState()) {
    _incoming = _server.incoming.listen((p) {
      emit(state.copyWith(pending: p));
      // The server settles an unanswered offer after 30 s. Clear it then, or
      // the stale offer would hide every later one from the prompt.
      p.decision.future.then((_) {
        if (!isClosed && state.pending?.id == p.id) {
          emit(state.copyWith(clearPending: true));
        }
      });
    });
    _incomingReq = _server.incomingRequests.listen((r) {
      emit(state.copyWith(pendingRequest: r));
    });
    _prog = _server.progress.listen((pr) {
      if (pr.isComplete) {
        final firstEnd = !_endedSessions.contains(pr.sessionId);
        final shown = state.progress?.sessionId == pr.sessionId;
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
        // Only the first end of a session that was on screen leaves a card.
        // An orphan terminal (QUIC, session already gone) has no sender and
        // no files: it only clears the card.
        final ended =
            !firstEnd || !shown || pr.senderAlias.isEmpty || pr.totalBytes == 0
            ? null
            : ReceiveOutcome(
                sessionId: pr.sessionId,
                senderAlias: pr.senderAlias,
                saved: pr.completedFiles,
                total: pr.totalFiles,
                bytes: pr.totalBytes,
              );
        emit(state.copyWith(clearProgress: true, speed: 0, outcome: ended));
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
      // Anonymous, opt-out telemetry: a LAN receive is a "download" the relay
      // never sees. Fire-and-forget; the service no-ops when disabled.
      _telemetry.recordReceive(bytes: f.size);
      _review?.noteSuccess();
    });
  }

  final TransferServer _server;
  final TelemetryService _telemetry;
  final ReviewPrompter? _review;
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

  /// Accepts [offer] (the one on screen; the current one when omitted). A
  /// newer offer that arrived meanwhile stays pending.
  void accept([PendingTransfer? offer]) => _settle(offer, true);

  void reject([PendingTransfer? offer]) => _settle(offer, false);

  void _settle(PendingTransfer? offer, bool yes) {
    final o = offer ?? state.pending;
    if (o == null) return;
    yes ? o.accept() : o.reject();
    if (state.pending?.id == o.id) emit(state.copyWith(clearPending: true));
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
