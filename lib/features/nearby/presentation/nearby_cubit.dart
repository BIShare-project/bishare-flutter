import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/identity/device_identity.dart';
import '../../../core/server/transfer_server.dart';
import '../../send/domain/sendable_file.dart';
import '../data/nearby_service.dart';
import '../domain/nearby_peer.dart';

/// UI state for the offline Nearby (MultipeerConnectivity) radar.
class NearbyState extends Equatable {
  const NearbyState({
    this.supported = false,
    this.active = false,
    this.peers = const [],
    this.transferring = false,
    this.direction,
    this.fileName,
    this.progress = 0,
    this.error,
  });

  /// Whether this platform has the native MPC plugin (iOS + macOS only).
  final bool supported;

  /// Whether advertising + browsing are running.
  final bool active;
  final List<NearbyPeer> peers;

  final bool transferring;
  final String? direction; // 'send' | 'receive'
  final String? fileName;
  final double progress;
  final String? error;

  NearbyState copyWith({
    bool? supported,
    bool? active,
    List<NearbyPeer>? peers,
    bool? transferring,
    String? direction,
    String? fileName,
    double? progress,
    String? error,
    bool clearError = false,
    bool clearFile = false,
  }) => NearbyState(
    supported: supported ?? this.supported,
    active: active ?? this.active,
    peers: peers ?? this.peers,
    transferring: transferring ?? this.transferring,
    direction: clearFile ? null : (direction ?? this.direction),
    fileName: clearFile ? null : (fileName ?? this.fileName),
    progress: progress ?? this.progress,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    supported,
    active,
    peers,
    transferring,
    direction,
    fileName,
    progress,
    error,
  ];
}

/// Drives the offline Nearby feature: starts/stops MPC advertising+browsing,
/// exposes discovered peers, sends files, and routes received files back through
/// [TransferServer.ingestExternalFile] so they land in the same inbox/history as
/// LAN transfers.
class NearbyCubit extends Cubit<NearbyState> {
  NearbyCubit(this._service, this._identity, this._server)
    : super(NearbyState(supported: _service.isSupported));

  final NearbyService _service;
  final DeviceIdentity _identity;
  final TransferServer _server;
  StreamSubscription<NearbyEvent>? _sub;

  Future<void> start() async {
    if (!_service.isSupported) return;
    // onError swallows a MissingPluginException if the native plugin hasn't been
    // added to the Runner target yet — the radar still renders (empty/searching).
    _sub ??= _service.events().listen(_onEvent, onError: (_) {});
    try {
      await _service.configure(_identity.alias, _identity.fingerprint);
      await _service.start();
      emit(state.copyWith(active: true, clearError: true));
    } catch (_) {
      emit(state.copyWith(active: false));
    }
  }

  Future<void> stop() async {
    await _service.stop();
    emit(state.copyWith(active: false, peers: const []));
  }

  Future<void> connect(NearbyPeer peer) => _service.connect(peer.id);

  Future<void> sendFiles(NearbyPeer peer, List<SendableFile> files) async {
    final items = [
      for (final f in files)
        {'path': f.path, 'name': f.name, 'type': f.mimeType, 'size': f.size},
    ];
    await _service.send(peer.id, items);
  }

  void _onEvent(NearbyEvent e) {
    switch (e) {
      case NearbyPeersEvent(:final peers):
        emit(state.copyWith(peers: peers));
      case NearbyTransferStart(:final direction, :final fileName):
        emit(state.copyWith(
          transferring: true,
          direction: direction,
          fileName: fileName,
          progress: 0,
        ));
      case NearbyProgressEvent(:final direction, :final fileName, :final progress):
        emit(state.copyWith(
          transferring: true,
          direction: direction,
          fileName: fileName ?? state.fileName,
          progress: progress,
        ));
      case NearbyTransferDone():
        emit(state.copyWith(transferring: false, progress: 0, clearFile: true));
      case NearbyReceived(
        :final tempPath,
        :final fileName,
        :final fileType,
        :final size,
        :final senderAlias,
      ):
        // Finalize through the shared receive pipeline (naming + inbox + history).
        _server.ingestExternalFile(
          tempPath: tempPath,
          fileName: fileName,
          fileType: fileType,
          size: size,
          senderAlias: senderAlias,
        );
      case NearbyError(:final message):
        emit(state.copyWith(error: message, transferring: false));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _service.stop();
    return super.close();
  }
}
