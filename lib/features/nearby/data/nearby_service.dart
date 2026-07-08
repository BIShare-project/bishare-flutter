import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/nearby_peer.dart';

/// Typed events streamed from the native `BIShareNearbyPlugin` (MPC).
sealed class NearbyEvent {
  const NearbyEvent();
}

class NearbyPeersEvent extends NearbyEvent {
  const NearbyPeersEvent(this.peers);
  final List<NearbyPeer> peers;
}

class NearbyProgressEvent extends NearbyEvent {
  const NearbyProgressEvent(this.direction, this.fileName, this.progress);
  final String direction; // 'send' | 'receive'
  final String? fileName;
  final double progress;
}

class NearbyTransferStart extends NearbyEvent {
  const NearbyTransferStart(this.direction, this.fileName);
  final String direction;
  final String fileName;
}

class NearbyTransferDone extends NearbyEvent {
  const NearbyTransferDone(this.direction);
  final String direction;
}

class NearbyReceived extends NearbyEvent {
  const NearbyReceived({
    required this.tempPath,
    required this.fileName,
    required this.fileType,
    required this.size,
    required this.senderAlias,
  });
  final String tempPath;
  final String fileName;
  final String fileType;
  final int size;
  final String senderAlias;
}

class NearbyError extends NearbyEvent {
  const NearbyError(this.message);
  final String message;
}

/// Bridges the native MultipeerConnectivity plugin (`app.bishare/nearby`). Only
/// iOS + macOS implement it; on other platforms every call is a safe no-op and
/// [events] is empty, so the Nearby feature simply doesn't surface.
class NearbyService {
  static const _method = MethodChannel('app.bishare/nearby');
  static const _events = EventChannel('app.bishare/nearby/events');

  bool get isSupported => Platform.isIOS || Platform.isMacOS;

  Stream<NearbyEvent> events() {
    if (!isSupported) return const Stream<NearbyEvent>.empty();
    return _events
        .receiveBroadcastStream()
        .map(_parse)
        .where((e) => e != null)
        .cast<NearbyEvent>();
  }

  NearbyEvent? _parse(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    switch (m['event'] as String?) {
      case 'peers':
        final list = (m['peers'] as List)
            .map((e) => NearbyPeer.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
        return NearbyPeersEvent(list);
      case 'transferStart':
        return NearbyTransferStart(
          m['direction'] as String? ?? '',
          m['fileName'] as String? ?? '',
        );
      case 'progress':
        return NearbyProgressEvent(
          m['direction'] as String? ?? '',
          m['fileName'] as String?,
          (m['progress'] as num?)?.toDouble() ?? 0,
        );
      case 'transferDone':
        return NearbyTransferDone(m['direction'] as String? ?? '');
      case 'received':
        return NearbyReceived(
          tempPath: m['tempPath'] as String,
          fileName: m['fileName'] as String? ?? 'file',
          fileType: m['fileType'] as String? ?? 'application/octet-stream',
          size: (m['size'] as num?)?.toInt() ?? 0,
          senderAlias: m['senderAlias'] as String? ?? 'Nearby device',
        );
      case 'error':
        return NearbyError(m['message'] as String? ?? 'error');
      default:
        return null;
    }
  }

  Future<void> configure(String alias, String fingerprint) async {
    if (isSupported) {
      await _method.invokeMethod('configure', {
        'alias': alias,
        'fingerprint': fingerprint,
      });
    }
  }

  Future<void> start() async {
    if (isSupported) await _method.invokeMethod('start');
  }

  Future<void> stop() async {
    if (isSupported) await _method.invokeMethod('stop');
  }

  Future<void> connect(String peerId) async {
    if (isSupported) await _method.invokeMethod('connect', {'peerId': peerId});
  }

  /// [items] each: `{path, name, type, size}`.
  Future<void> send(String peerId, List<Map<String, dynamic>> items) async {
    if (isSupported) {
      await _method.invokeMethod('send', {'peerId': peerId, 'items': items});
    }
  }
}
