import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/identity/device_identity.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/webrtc/ice_servers.dart';
import '../../history/data/history_repository.dart';
import '../../room/data/webrtc_signaling.dart';

/// The app↔web "Nearby" bridge — makes this device appear in the browser
/// Nearby tab on bishare.app/transfer (and browsers appear here), by joining
/// the SAME IP-keyed signaling room (`/api/v1/nearby/ws`, no code) and speaking
/// the web client's exact wire protocol (`bishare-web/src/lib/nearby/webrtc.ts`):
///
///  - signal kinds `offer` / `answer` / `ice` / `cancel`, NO sid — sessions are
///    peer-keyed, one transfer per peer pair at a time;
///  - `offer` carries `{sdp:{type,sdp}, meta:{name,size,mime}}` so the receiver
///    can prompt before answering; `answer` payload IS the description;
///    `ice` payload IS the candidate JSON;
///  - file bytes stream as raw binary chunks over the DataChannel with
///    backpressure; the receiver replies with the string `"received"` once the
///    file is SAVED, which is the sender's real delivery confirmation.
///
/// Only runs while the device is on a LAN (a private IPv4 exists): the room is
/// keyed by public IP, and on cellular CGNAT that would group strangers.

const _ackReceived = 'received';
const _chunkSize = 256 * 1024;
const _bufferHigh = 8 * 1024 * 1024;

class WebNearbyPeer {
  const WebNearbyPeer({required this.peerId, required this.alias, required this.emoji});
  final String peerId;
  final String alias;
  final String emoji;
}

/// An incoming offer from a browser — surfaced as an accept/decline prompt.
class WebNearbyIncomingRequest {
  WebNearbyIncomingRequest({
    required this.from,
    required this.fromAlias,
    required this.name,
    required this.size,
    required this.mime,
    required void Function() onAccept,
    required void Function() onDecline,
  })  : _onAccept = onAccept,
        _onDecline = onDecline;

  final String from;
  final String fromAlias;
  final String name;
  final int size;
  final String mime;
  final void Function() _onAccept;
  final void Function() _onDecline;
  bool _answered = false;

  void accept() {
    if (_answered) return;
    _answered = true;
    _onAccept();
  }

  void decline() {
    if (_answered) return;
    _answered = true;
    _onDecline();
  }
}

sealed class WebNearbyEvent {
  const WebNearbyEvent();
}

class WebNearbyPeersChanged extends WebNearbyEvent {
  const WebNearbyPeersChanged(this.peers);
  final List<WebNearbyPeer> peers;
}

class WebNearbyIncoming extends WebNearbyEvent {
  const WebNearbyIncoming(this.request);
  final WebNearbyIncomingRequest request;
}

class WebNearbySendProgress extends WebNearbyEvent {
  const WebNearbySendProgress(this.peerId, this.sent, this.total);
  final String peerId;
  final int sent;
  final int total;
}

class WebNearbySendDone extends WebNearbyEvent {
  const WebNearbySendDone(this.peerId, this.name);
  final String peerId;
  final String name;
}

class WebNearbySendError extends WebNearbyEvent {
  const WebNearbySendError(this.peerId, this.name, this.message);
  final String peerId;
  final String name;
  final String message;
}

class WebNearbyReceiveDone extends WebNearbyEvent {
  const WebNearbyReceiveDone(this.file);
  final ReceivedFile file;
}

class _PeerSession {
  _PeerSession(this.peerId, this.role);
  final String peerId;
  final String role; // 'send' | 'recv'
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  // sender
  File? file;
  String? name;
  int size = 0;
  bool sentComplete = false;
  bool notified = false;
  // receiver
  Map<String, dynamic>? meta;
  IOSink? sink;
  File? outFile;
  int received = 0;
  bool remoteReady = false;
  final List<RTCIceCandidate> pendingIce = [];
}

class WebNearbyService {
  WebNearbyService(this._identity, this._server, this._history);

  final DeviceIdentity _identity;
  final TransferServer _server;
  final HistoryRepository _history;

  final _events = StreamController<WebNearbyEvent>.broadcast();
  Stream<WebNearbyEvent> get events => _events.stream;

  final _peers = <String, WebNearbyPeer>{};
  List<WebNearbyPeer> get peers => _peers.values.toList();

  final _sessions = <String, _PeerSession>{}; // peerId → session
  // `ice` that races ahead of its `offer` while the pc awaits the ICE fetch —
  // same failure mode we fixed in the rooms path; hold and adopt, never drop.
  final _earlyIce = <String, List<RTCIceCandidate>>{};
  static const _earlyIceMax = 64;

  WebrtcSignaling? _sig;
  bool _running = false;
  bool get running => _running;
  Timer? _retry;

  /// Connect to the nearby signaling room. No-op when already running or when
  /// the device has no LAN address (cellular CGNAT would group strangers).
  Future<void> start() async {
    if (_running) return;
    final ip = await LocalIp.resolve().catchError((Object _) => '');
    if (ip.isEmpty) return;
    _running = true;
    _connect();
  }

  /// True for peers that are native BIShare apps, not browsers. Apps announce
  /// `kind: 'app'`; builds that predate the field are caught by their peerId
  /// shape — apps join with their device fingerprint (a 36-char UUID) while
  /// browsers mint 6-char session ids. App peers are hidden from the roster:
  /// app↔app transfers take the native LAN path, and listing them here would
  /// duplicate every device that discovery already shows.
  static final _uuidRe = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static bool _isAppPeer(SignalPeer p) =>
      p.kind == 'app' || (p.kind.isEmpty && _uuidRe.hasMatch(p.peerId));

  void _connect() {
    if (!_running) return;
    _sig?.close();
    final self = SignalPeer(
      peerId: _identity.fingerprint,
      alias: _identity.alias,
      emoji: (Platform.isAndroid || Platform.isIOS) ? '📱' : '💻',
      kind: 'app',
    );
    // Warm the TURN cache before any offer can arrive.
    unawaited(fetchWebrtcIceServers());
    final sig = WebrtcSignaling(self)
      ..onPeers = (list) {
        _peers
          ..clear()
          ..addEntries(list.where((p) => !_isAppPeer(p)).map((p) => MapEntry(
              p.peerId, WebNearbyPeer(peerId: p.peerId, alias: p.alias, emoji: p.emoji))));
        _emitPeers();
      }
      ..onPeerJoined = (p) {
        if (_isAppPeer(p)) return;
        _peers[p.peerId] =
            WebNearbyPeer(peerId: p.peerId, alias: p.alias, emoji: p.emoji);
        _emitPeers();
      }
      ..onPeerLeft = (id) {
        _peers.remove(id);
        _teardown(id);
        _emitPeers();
      }
      ..onSignal = (s) {
        _onSignal(s);
      }
      ..onClose = () {
        _peers.clear();
        _emitPeers();
        // Keep the bridge alive across blips while enabled.
        if (_running) {
          _retry?.cancel();
          _retry = Timer(const Duration(seconds: 4), _connect);
        }
      };
    _sig = sig;
    sig.connect();
  }

  Future<void> stop() async {
    _running = false;
    _retry?.cancel();
    _retry = null;
    for (final id in _sessions.keys.toList()) {
      _teardown(id);
    }
    _earlyIce.clear();
    _sig?.close();
    _sig = null;
    _peers.clear();
    _emitPeers();
  }

  void _emitPeers() => _events.add(WebNearbyPeersChanged(peers));

  String _aliasOf(String peerId) => _peers[peerId]?.alias ?? 'Browser';

  // ── sender ──

  Future<void> sendFile(String peerId, File file, {String? name, String? mime}) async {
    final fileName = name ?? file.uri.pathSegments.last;
    try {
      _teardown(peerId); // one transfer per pair — replace any stale session
      final s = _PeerSession(peerId, 'send')
        ..file = file
        ..name = fileName;
      _sessions[peerId] = s;
      final pc = await _newPc(peerId);
      if (_sessions[peerId] != s) return; // torn down while awaiting
      s.pc = pc;
      final dc = await pc.createDataChannel('file', RTCDataChannelInit()..ordered = true);
      s.dc = dc;
      s.size = await file.length();
      dc.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          unawaited(_pump(peerId));
        } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
          // Closed after every byte was handed over = receiver saved + left.
          if (s.sentComplete) _notifySendDone(peerId);
        }
      };
      dc.onMessage = (msg) {
        if (!msg.isBinary && msg.text == _ackReceived) _notifySendDone(peerId);
      };
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sig?.signal(peerId, 'offer', {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
        'meta': {
          'name': fileName,
          'size': s.size,
          'mime': mime ?? 'application/octet-stream',
        },
      });
    } catch (e) {
      _teardown(peerId);
      _events.add(WebNearbySendError(peerId, fileName, e.toString()));
    }
  }

  Future<void> _pump(String peerId) async {
    final s = _sessions[peerId];
    final dc = s?.dc;
    final file = s?.file;
    if (s == null || dc == null || file == null) return;
    try {
      final raf = await file.open();
      try {
        int offset = 0;
        while (offset < s.size) {
          if (_sessions[peerId] != s) return; // cancelled mid-send
          if ((dc.bufferedAmount ?? 0) > _bufferHigh) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            continue;
          }
          final bytes = await raf.read(min(_chunkSize, s.size - offset));
          await dc.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)));
          offset += bytes.length;
          _events.add(WebNearbySendProgress(peerId, offset, s.size));
        }
      } finally {
        await raf.close();
      }
      s.sentComplete = true; // done fires on the receiver's ack (or clean close)
    } catch (e) {
      final name = s.name ?? 'file';
      _teardown(peerId);
      _events.add(WebNearbySendError(peerId, name, e.toString()));
    }
  }

  void _notifySendDone(String peerId) {
    final s = _sessions[peerId];
    if (s == null || s.notified) return;
    s.notified = true;
    _events.add(WebNearbySendDone(peerId, s.name ?? 'file'));
    _teardown(peerId);
  }

  // ── receiver ──

  Future<void> _onSignal(IncomingSignal m) async {
    final kind = m.kind;
    final p = m.payload;
    // Room signals carry a sid — not ours (rooms run on a code-scoped socket,
    // but keep the guard in case of cross-wiring).
    if (p.containsKey('sid')) return;

    if (kind == 'offer') {
      final sdp = (p['sdp'] as Map?)?.cast<String, dynamic>();
      final meta = (p['meta'] as Map?)?.cast<String, dynamic>();
      if (sdp == null || meta == null) return;
      _teardown(m.from); // replace any stale session with this peer
      final s = _PeerSession(m.from, 'recv')..meta = meta;
      _sessions[m.from] = s;
      final early = _earlyIce.remove(m.from);
      if (early != null) s.pendingIce.addAll(early);
      final pc = await _newPc(m.from);
      if (_sessions[m.from] != s) return;
      s.pc = pc;
      pc.onDataChannel = (channel) {
        s.dc = channel;
        channel.onMessage = (msg) => _onData(m.from, msg);
      };
      await pc.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?));
      s.remoteReady = true;
      await _flushIce(m.from);
      _events.add(WebNearbyIncoming(WebNearbyIncomingRequest(
        from: m.from,
        fromAlias: _aliasOf(m.from),
        name: (meta['name'] as String?) ?? 'file',
        size: (meta['size'] as num?)?.toInt() ?? 0,
        mime: (meta['mime'] as String?) ?? 'application/octet-stream',
        onAccept: () => unawaited(_accept(m.from, s)),
        onDecline: () {
          _sig?.signal(m.from, 'cancel', const {});
          _teardown(m.from);
        },
      )));
    } else if (kind == 'answer') {
      final s = _sessions[m.from];
      final pc = s?.pc;
      if (s == null || pc == null) return;
      await pc.setRemoteDescription(
          RTCSessionDescription(p['sdp'] as String?, p['type'] as String?));
      s.remoteReady = true;
      await _flushIce(m.from);
    } else if (kind == 'ice') {
      final cand = RTCIceCandidate(
        p['candidate'] as String?,
        p['sdpMid'] as String?,
        (p['sdpMLineIndex'] as num?)?.toInt(),
      );
      final s = _sessions[m.from];
      if (s == null) {
        final held = _earlyIce.putIfAbsent(m.from, () => []);
        if (held.length < _earlyIceMax) held.add(cand);
        return;
      }
      if (s.remoteReady && s.pc != null) {
        await s.pc!.addCandidate(cand);
      } else {
        s.pendingIce.add(cand);
      }
    } else if (kind == 'cancel') {
      final s = _sessions[m.from];
      if (s != null && s.role == 'send') {
        final name = s.name ?? 'file';
        _teardown(m.from);
        _events.add(WebNearbySendError(m.from, name, 'declined'));
      } else {
        _teardown(m.from);
      }
    }
  }

  Future<void> _accept(String peerId, _PeerSession s) async {
    final pc = s.pc;
    if (_sessions[peerId] != s || pc == null) return;
    try {
      s.sink = await _openOutput(s);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      // The web reads the description straight from the payload — do not wrap.
      _sig?.signal(peerId, 'answer', {'type': answer.type, 'sdp': answer.sdp});
    } catch (_) {
      _sig?.signal(peerId, 'cancel', const {});
      _teardown(peerId);
    }
  }

  void _onData(String peerId, RTCDataChannelMessage msg) {
    final s = _sessions[peerId];
    if (s == null || !msg.isBinary || s.sink == null) return;
    s.sink!.add(msg.binary);
    s.received += msg.binary.length;
    final total = (s.meta?['size'] as num?)?.toInt() ?? 0;
    if (total >= 0 && s.received >= total) unawaited(_finishReceive(peerId));
  }

  Future<void> _finishReceive(String peerId) async {
    final s = _sessions[peerId];
    final out = s?.outFile;
    if (s == null || out == null) return;
    try {
      await s.sink?.flush();
      await s.sink?.close();
    } catch (_) {
      _teardown(peerId);
      return;
    }
    s.sink = null;
    final received = ReceivedFile(
      fileName: out.uri.pathSegments.last,
      savedPath: out.path,
      size: s.received,
      senderAlias: _aliasOf(peerId),
      receivedAt: DateTime.now(),
      verified: false,
      fileType: (s.meta?['mime'] as String?) ?? 'application/octet-stream',
      encrypted: false,
    );
    try {
      await _history.recordReceived(received);
    } catch (_) {/* history best-effort */}
    // Delivery ack — the sender's "sent" means saved, not just transmitted.
    try {
      await s.dc?.send(RTCDataChannelMessage(_ackReceived));
    } catch (_) {/* channel gone — sender falls back to close-after-complete */}
    _events.add(WebNearbyReceiveDone(received));
    // Give the ack a beat to flush before closing our side.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (_sessions[peerId] == s) _teardown(peerId);
    });
  }

  Future<IOSink> _openOutput(_PeerSession s) async {
    final name = (s.meta?['name'] as String?) ?? 'file';
    final dir = _server.saveDirectory;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final dirPath = dir.path;
    final safe = name.replaceAll(RegExp(r'[/\\]'), '_');
    var target = File('$dirPath${Platform.pathSeparator}$safe');
    var i = 1;
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    while (await target.exists()) {
      target = File('$dirPath${Platform.pathSeparator}$base ($i)$ext');
      i++;
    }
    s.outFile = target;
    return target.openWrite();
  }

  Future<RTCPeerConnection> _newPc(String peerId) async {
    final ice = await fetchWebrtcIceServers();
    final pc = await createPeerConnection({'iceServers': ice});
    pc.onIceCandidate = (c) {
      // Payload is the candidate JSON itself — the web adds it directly.
      final map = c.toMap();
      _sig?.signal(peerId, 'ice', (map as Map).cast<String, dynamic>());
    };
    pc.onConnectionState = (state) {
      if (kDebugMode) debugPrint('[web-nearby] $peerId pcState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        final s = _sessions[peerId];
        if (s != null && s.role == 'send' && !s.notified) {
          _events.add(WebNearbySendError(peerId, s.name ?? 'file', 'connection failed'));
        }
        _teardown(peerId);
      }
    };
    return pc;
  }

  Future<void> _flushIce(String peerId) async {
    final s = _sessions[peerId];
    final pc = s?.pc;
    if (s == null || pc == null) return;
    for (final c in s.pendingIce) {
      await pc.addCandidate(c);
    }
    s.pendingIce.clear();
  }

  void _teardown(String peerId) {
    _earlyIce.remove(peerId);
    final s = _sessions.remove(peerId);
    if (s == null) return;
    try {
      s.dc?.close();
      s.pc?.close();
    } catch (_) {/* noop */}
    final total = (s.meta?['size'] as num?)?.toInt() ?? 0;
    if (s.sink != null && s.received < total) {
      s.sink?.close().catchError((_) {});
    }
  }
}
