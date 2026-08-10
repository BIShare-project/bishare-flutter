import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/error/exceptions.dart';
import '../../../features/history/data/history_repository.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../../core/telemetry/telemetry_service.dart';
import '../data/transfer_client.dart';
import '../domain/sendable_file.dart';

enum SendStatus { idle, sending, done, error, pinRequired }

class SendState extends Equatable {
  const SendState({
    this.status = SendStatus.idle,
    this.deviceAlias = '',
    this.fileName = '',
    this.sent = 0,
    this.total = 0,
    this.speed = 0,
    this.message = '',
    this.transport = 'TCP',
  });

  final SendStatus status;
  final String deviceAlias;
  final String fileName;
  final int sent;
  final int total;
  final double speed; // bytes/sec
  final String message;
  final String transport; // 'TCP' | 'QUIC' — the transport actually used

  double get fraction => total == 0 ? 0 : sent / total;

  /// Seconds remaining, or null when unknown.
  double? get etaSeconds =>
      speed <= 0 || total <= sent ? null : (total - sent) / speed;

  SendState copyWith({
    SendStatus? status,
    String? deviceAlias,
    String? fileName,
    int? sent,
    int? total,
    double? speed,
    String? message,
    String? transport,
  }) => SendState(
    status: status ?? this.status,
    deviceAlias: deviceAlias ?? this.deviceAlias,
    fileName: fileName ?? this.fileName,
    sent: sent ?? this.sent,
    total: total ?? this.total,
    speed: speed ?? this.speed,
    message: message ?? this.message,
    transport: transport ?? this.transport,
  );

  @override
  List<Object?> get props => [
    status,
    deviceAlias,
    fileName,
    sent,
    total,
    speed,
    message,
    transport,
  ];
}

/// Drives one outgoing transfer and exposes progress (with live speed + ETA).
/// Cancel notifies the receiver via `/api/v1/cancel`; [retryLast] re-sends the
/// last batch after a failure.
class SendCubit extends Cubit<SendState> {
  SendCubit(this._client, this._history, this._telemetry)
    : super(const SendState());

  final TransferClient _client;
  final HistoryRepository _history;
  final TelemetryService _telemetry;
  CancelToken? _cancelToken;
  DiscoveredDevice? _device;
  String? _sessionId;
  final _sw = Stopwatch();

  // Remembered for retry.
  List<SendableFile>? _lastFiles;
  DiscoveredDevice? _lastDevice;
  String? _lastPin;

  Future<void> sendFiles(
    List<SendableFile> files,
    DiscoveredDevice device, {
    String? pin,
  }) async {
    _cancelToken = CancelToken();
    _device = device;
    _lastFiles = files;
    _lastDevice = device;
    _lastPin = pin;
    _sw
      ..reset()
      ..start();
    final total = files.fold<int>(0, (s, f) => s + f.size);
    emit(
      SendState(
        status: SendStatus.sending,
        deviceAlias: device.alias,
        total: total,
      ),
    );
    try {
      await _client.send(
        files,
        device,
        pin: pin,
        cancelToken: _cancelToken,
        onSession: (sid) => _sessionId = sid,
        onTransport: (t) => emit(state.copyWith(transport: t)),
        onProgress: (i, count, name, overallSent, overallTotal) {
          final secs = _sw.elapsedMilliseconds / 1000;
          emit(
            state.copyWith(
              fileName: name,
              sent: overallSent,
              total: overallTotal,
              speed: secs > 0.2 ? overallSent / secs : state.speed,
            ),
          );
        },
      );
      for (final f in files) {
        await _history.recordSent(
          fileName: f.name,
          size: f.size,
          fileType: f.mimeType,
          deviceAlias: device.alias,
          deviceFingerprint: device.fingerprint,
          encrypted:
              true, // LAN transfers negotiate E2E when the peer advertises a key
        );
      }
      emit(state.copyWith(status: SendStatus.done));
      // Anonymous, aggregate-only: a nearby/LAN transfer completed. Lets the
      // public stats reflect real usage that never touches the relay. No PII;
      // opt-out-able; fire-and-forget.
      _telemetry.recordTransfer(
        bytes: total,
        transport: state.transport == 'QUIC' ? 'quic' : 'lan',
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        emit(state.copyWith(status: SendStatus.idle));
      } else {
        emit(
          state.copyWith(
            status: SendStatus.error,
            message: e.message ?? 'send.send_failed'.tr(),
          ),
        );
      }
    } on TransferHttpException catch (e) {
      // 403 carries the real reason ("Wrong PIN" vs "Transfer rejected") — use
      // it instead of guessing from _lastPin (a correct PIN can still be
      // declined). 401 is always a PIN prompt.
      final reason = (e.body ?? '').toLowerCase();
      final rejected =
          e.statusCode == BIShareStatus.forbidden &&
          (reason.contains('reject') || reason.contains('declin'));
      final pinIssue =
          e.statusCode == BIShareStatus.pinRequired ||
          (e.statusCode == BIShareStatus.forbidden &&
              !rejected &&
              (reason.contains('pin') || _lastPin != null));
      if (rejected) {
        emit(
          state.copyWith(
            status: SendStatus.error,
            message: 'send.declined'.tr(
              namedArgs: {'alias': state.deviceAlias},
            ),
          ),
        );
      } else if (pinIssue) {
        emit(
          state.copyWith(
            status: SendStatus.pinRequired,
            message: _lastPin != null ? 'send.wrong_pin'.tr() : '',
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: SendStatus.error,
            message: _describe(e.statusCode),
          ),
        );
      }
    } finally {
      _sw.stop();
    }
  }

  /// Submit a PIN entered by the user and retry the last batch.
  Future<void> submitPin(String pin) async {
    final files = _lastFiles;
    final device = _lastDevice;
    if (files == null || device == null) return;
    await sendFiles(files, device, pin: pin);
  }

  /// Re-send the last batch (after an error).
  Future<void> retryLast() async {
    final files = _lastFiles;
    final device = _lastDevice;
    if (files == null || device == null) return;
    await sendFiles(files, device, pin: _lastPin);
  }

  /// Cancel the in-flight transfer and tell the receiver to abort too.
  Future<void> cancel() async {
    _cancelToken?.cancel('user_cancelled');
    final sid = _sessionId;
    final dev = _device;
    if (sid != null && dev != null) {
      await _client.cancel(sid, dev);
    }
    emit(const SendState());
  }

  void reset() => emit(const SendState());

  /// Reverse flow: ask [device] to send us files. Returns true if accepted.
  /// Blocks until the peer's user decides (auto-declines after 60s).
  Future<bool> requestFiles(DiscoveredDevice device, String? message) async {
    final res = await _client.sendFileRequest(device, message);
    return res.accepted;
  }

  String _describe(int status) => switch (status) {
    BIShareStatus.pinRequired => 'send.pin_required'.tr(),
    BIShareStatus.forbidden => 'send.transfer_forbidden'.tr(),
    BIShareStatus.busy => 'send.device_busy'.tr(),
    _ => 'send.send_failed_status'.tr(namedArgs: {'status': '$status'}),
  };
}
