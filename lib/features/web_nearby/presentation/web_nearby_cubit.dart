import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/config/feature_flags.dart';
import '../data/web_nearby_service.dart';

class WebNearbyState {
  const WebNearbyState({
    this.peers = const [],
    this.running = false,
    this.sendingTo = const {},
  });

  final List<WebNearbyPeer> peers;
  final bool running;

  /// Peer ids with a send in flight — the row shows a spinner instead of the
  /// send button.
  final Set<String> sendingTo;

  WebNearbyState copyWith({
    List<WebNearbyPeer>? peers,
    bool? running,
    Set<String>? sendingTo,
  }) =>
      WebNearbyState(
        peers: peers ?? this.peers,
        running: running ?? this.running,
        sendingTo: sendingTo ?? this.sendingTo,
      );
}

/// Runs the app↔web Nearby bridge while the app is FOREGROUND and the remote
/// flag allows it: browsers on the same network appear as send targets, and
/// their offers surface as accept prompts (listened to in the main shell).
class WebNearbyCubit extends Cubit<WebNearbyState> with WidgetsBindingObserver {
  WebNearbyCubit(this._service, this._flags) : super(const WebNearbyState()) {
    _sub = _service.events.listen(_onEvent);
    _flags.addListener(_applyFlag);
    WidgetsBinding.instance.addObserver(this);
    _applyFlag();
  }

  final WebNearbyService _service;
  final FeatureFlags _flags;
  StreamSubscription<WebNearbyEvent>? _sub;
  bool _foreground = true;

  void _applyFlag() {
    if (_flags.webNearbyEnabled && _foreground) {
      unawaited(_start());
    } else {
      unawaited(_stopService());
    }
  }

  Future<void> _start() async {
    await _service.start();
    emit(state.copyWith(running: _service.running, peers: _service.peers));
  }

  Future<void> _stopService() async {
    if (!_service.running) return;
    await _service.stop();
    emit(state.copyWith(running: false, peers: const []));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _applyFlag();
  }

  void _onEvent(WebNearbyEvent event) {
    switch (event) {
      case WebNearbyPeersChanged(:final peers):
        emit(state.copyWith(peers: peers));
      case WebNearbySendDone(:final peerId):
      case WebNearbySendError(:final peerId):
        emit(state.copyWith(sendingTo: {...state.sendingTo}..remove(peerId)));
      default:
        break;
    }
  }

  /// Send [files] to [peerId] sequentially (the wire allows one transfer per
  /// peer pair at a time).
  Future<void> sendFiles(String peerId, List<File> files) async {
    if (files.isEmpty) return;
    emit(state.copyWith(sendingTo: {...state.sendingTo, peerId}));
    for (final f in files) {
      await _service.sendFile(peerId, f);
      // Wait for this transfer to settle (done/error clears sendingTo) before
      // starting the next — the service replaces the session per peer.
      while (_service.running && state.sendingTo.contains(peerId)) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!state.sendingTo.contains(peerId)) break;
      }
      if (f != files.last) {
        emit(state.copyWith(sendingTo: {...state.sendingTo, peerId}));
      }
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    _flags.removeListener(_applyFlag);
    await _sub?.cancel();
    await _service.stop();
    return super.close();
  }
}
