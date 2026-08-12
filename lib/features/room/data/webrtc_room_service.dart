import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/identity/device_identity.dart';
import '../../../core/webrtc/ice_servers.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';
import '../domain/room_models.dart';
import 'room_service.dart' show RoomEvent, RoomMemberJoinedEvent, RoomMemberLeftEvent, RoomFileAddedEvent, RoomUploadStartEvent, RoomUploadDoneEvent;
import 'webrtc_signaling.dart';

const _emojis = ['🦊', '🐼', '🐧', '🦉', '🐙', '🦜', '🐳', '🦄', '🐝', '🦩'];
const _chunkSize = 256 * 1024;
const _bufferHigh = 8 * 1024 * 1024;
// STUN for direct/same-network paths; TURN as a relay fallback so transfers
// still connect when the network blocks peer-to-peer (client isolation, strict
// NAT). Direct paths are preferred — TURN is a last resort.
// TURN/STUN come from the shared core/webrtc/ice_servers.dart helper (same
// GET /api/v1/webrtc/ice source the web client uses), so rooms and the web
// nearby bridge share one credential cache.

class _Session {
  _Session(this.sid, this.peerId, this.pc, this.role);
  final String sid;
  final String peerId;
  final RTCPeerConnection pc;
  final String role; // 'send' | 'recv'
  RTCDataChannel? dc;
  File? file; // sender
  Map<String, dynamic>? meta; // receiver: {name,size,mime}
  int received = 0;
  final List<int> chunks = [];
  IOSink? sink; // receiver: streaming to disk
  File? outFile;
  bool remoteReady = false;
  final List<RTCIceCandidate> pendingIce = [];
}

/// Browser-compatible WebRTC room for the app — same wire protocol the web
/// local (P2P) room speaks (signaling via [WebrtcSignaling], file bytes over
/// DTLS DataChannels). Lets the app auto-join a room a web browser hosts when
/// no Bonjour host is found on the LAN. Files fly peer-to-peer; only SDP/ICE
/// touches the relay.
class WebrtcRoomService {
  WebrtcRoomService(this._identity, this._server, this._history);

  final DeviceIdentity _identity;
  final TransferServer _server;
  final HistoryRepository _history;

  final _events = StreamController<RoomEvent>.broadcast();
  Stream<RoomEvent> get events => _events.stream;

  // fileId → local path. WebRTC files are pushed and saved on arrival (or are
  // our own originals), so "download" just returns the already-saved file.
  final _savedPaths = <String, String>{};

  /// A WebRTC room file is already on disk (received) or is our own original —
  /// return it directly rather than re-fetching.
  Future<File> downloadFile(RoomFile file) async {
    final p = _savedPaths[file.id];
    if (p == null) throw Exception('File is no longer available');
    return File(p);
  }

  Future<File> downloadToTemp(RoomFile file) => downloadFile(file);

  WebrtcSignaling? _sig;
  final _sessions = <String, _Session>{}; // sid → session
  // Trickled `rice` candidates that arrive for a sid BEFORE its session exists
  // (the roffer handler awaits the ICE-server fetch first). Adopted into the
  // session's pendingIce when the roffer lands; bounded so junk sids can't grow.
  final _earlyIce = <String, List<RTCIceCandidate>>{};
  static const _earlyIceMax = 64;
  final _members = <String, RoomMember>{}; // peerId → member
  String _code = '';
  String? _peerId;
  int _sidCounter = 0;

  final _rand = Random();
  String _newSid() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_sidCounter++}-${_rand.nextInt(1 << 32).toRadixString(36)}';

  /// Connect the signaling for [code] and wire the peer/roster/SDP callbacks.
  /// [firstPeer] (join path) completes with the first peer seen so the caller
  /// can confirm it's a live room; omitted on the host path (just stay open).
  void _startSignaling(String code, {Completer<SignalPeer?>? firstPeer}) {
    // The service is a singleton — clear any prior room's state first.
    for (final sid in _sessions.keys.toList()) {
      _teardown(sid);
    }
    _earlyIce.clear();
    _members.clear();
    _savedPaths.clear();
    _sig?.close();
    // Warm the TURN-credential cache now, so answering the first roffer isn't
    // delayed by a network fetch (that delay is what let candidates race in).
    unawaited(fetchWebrtcIceServers());
    _code = code.trim().toUpperCase();
    _peerId = _identity.fingerprint;
    final self = SignalPeer(
      peerId: _peerId!,
      alias: _identity.alias,
      emoji: _emojis[_rand.nextInt(_emojis.length)],
    );
    void offerPeer(SignalPeer? p) {
      if (firstPeer != null && !firstPeer.isCompleted) firstPeer.complete(p);
    }
    final sig = WebrtcSignaling(self, _code)
      ..onPeers = (list) {
        for (final p in list) {
          if (_members[p.peerId] == null) _events.add(RoomMemberJoinedEvent(_memberOf(p)));
          _members[p.peerId] = _memberOf(p);
        }
        if (list.isNotEmpty) offerPeer(list.first);
      }
      ..onPeerJoined = (p) {
        _members[p.peerId] = _memberOf(p);
        _events.add(RoomMemberJoinedEvent(_memberOf(p)));
        offerPeer(p);
      }
      ..onPeerLeft = (id) {
        _members.remove(id);
        _events.add(RoomMemberLeftEvent(id));
      }
      ..onSignal = (s) {
        _onSignal(s);
      }
      ..onClose = () {};
    _sig = sig;
    sig.connect();
  }

  /// Advertise an app-hosted local (Bonjour) room over WebRTC signaling too, so
  /// web peers — which can't do Bonjour — can find and join it. No peer-wait:
  /// stay connected and handle peers/files as they arrive. Runs ALONGSIDE the
  /// Bonjour host (dual transport); the cubit fans shares to both.
  void hostLocal(String code) => _startSignaling(code);

  /// Try to join a WebRTC room by code. Resolves to (session, members, files)
  /// once at least one peer appears within [timeout] (i.e. it IS a live web
  /// room); returns null otherwise so the caller can fall back to a relay room.
  Future<(RoomSession, List<RoomMember>, List<RoomFile>)?> joinWebrtc(
    String code, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final firstPeer = Completer<SignalPeer?>();
    _startSignaling(code, firstPeer: firstPeer);

    // Wait for the first peer (= confirmation this is a real web room).
    final peer = await firstPeer.future.timeout(timeout, onTimeout: () => null);
    if (peer == null) {
      _sig?.close();
      _sig = null;
      return null;
    }

    final session = RoomSession(
      code: _code,
      hostFingerprint: peer.peerId,
      hostAlias: peer.alias,
      isHost: false,
      remote: false,
    );
    return (session, _members.values.toList(), <RoomFile>[]);
  }

  RoomMember _memberOf(SignalPeer p) =>
      RoomMember(fingerprint: p.peerId, alias: p.alias, deviceType: 'web');

  /// True when this service already holds [id] (received over WebRTC or our own
  /// share) — used by the cubit to route a download to the right transport in a
  /// dual (Bonjour + WebRTC) local room.
  bool hasFile(String id) => _savedPaths.containsKey(id);

  // ── outgoing: broadcast a file to every peer ──
  // [emitOwn] false in a dual-transport local room, where the Bonjour side
  // already surfaces the host's own file (avoids a duplicate list entry).
  Future<void> addFile(File file, {required String name, required String mime, bool emitOwn = true}) async {
    _events.add(RoomUploadStartEvent(_identity.alias, name));
    final peers = _members.keys.toList();
    await Future.wait(peers.map((id) => _sendTo(id, file, name, mime).catchError((_) {})));
    _events.add(const RoomUploadDoneEvent());
    if (!emitOwn) return;
    // Surface our own shared file locally too, so the sender sees it in the list.
    final ownId = _newSid();
    _savedPaths[ownId] = file.path;
    _events.add(RoomFileAddedEvent(RoomFile(
      id: ownId,
      fileName: name,
      fileType: mime,
      size: await file.length(),
      ownerFingerprint: _identity.fingerprint,
      ownerAlias: _identity.alias,
    )));
  }

  Future<void> _sendTo(String peerId, File file, String name, String mime) async {
    final sid = _newSid();
    final pc = await _newPc(sid, peerId);
    final dc = await pc.createDataChannel('file', RTCDataChannelInit()..ordered = true);
    final s = _Session(sid, peerId, pc, 'send')..dc = dc..file = file;
    _sessions[sid] = s;
    final size = await file.length();
    dc.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _pump(sid, name, size, mime);
      }
    };
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _sig?.signal(peerId, 'roffer', {
      'sid': sid,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
      'meta': {'name': name, 'size': size, 'mime': mime},
    });
  }

  Future<void> _pump(String sid, String name, int size, String mime) async {
    final s = _sessions[sid];
    if (s?.dc == null || s?.file == null) return;
    final dc = s!.dc!;
    final raf = await s.file!.open();
    try {
      int offset = 0;
      while (offset < size) {
        if (!_sessions.containsKey(sid)) return;
        // Basic backpressure: pause if the send buffer is backing up.
        final buffered = dc.bufferedAmount ?? 0;
        if (buffered > _bufferHigh) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        final end = min(offset + _chunkSize, size);
        final bytes = await raf.read(end - offset);
        await dc.send(RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)));
        offset += bytes.length;
      }
    } finally {
      await raf.close();
    }
    // Close after a short beat so the tail flushes.
    Future<void>.delayed(const Duration(seconds: 2), () => _teardown(sid));
  }

  // ── incoming signaling ──
  Future<void> _onSignal(IncomingSignal m) async {
    final p = m.payload;
    final sid = p['sid'] as String?;
    if (sid == null) return;

    if (m.kind == 'roffer') {
      // _newPc awaits the ICE-server fetch (network!), and the offerer's
      // trickled `rice` candidates land while that await is in flight — before
      // the session exists. They are buffered in [_earlyIce] (see the rice
      // branch) and adopted below; dropping them stalled ICE forever (web
      // stuck "uploading", app silent).
      if (kDebugMode) debugPrint('[wrtc-room] $sid roffer from ${m.from}');
      final pc = await _newPc(sid, m.from);
      final meta = (p['meta'] as Map?)?.cast<String, dynamic>();
      final s = _Session(sid, m.from, pc, 'recv')..meta = meta;
      _sessions[sid] = s;
      final early = _earlyIce.remove(sid);
      if (early != null) s.pendingIce.addAll(early);
      // Open the output sink up-front (not lazily on the first chunk) so rapid
      // chunks can't race two opens for the same file.
      if (meta != null) s.sink = await _openOutput(s);
      pc.onDataChannel = (channel) {
        if (kDebugMode) debugPrint('[wrtc-room] $sid dc arrived');
        s.dc = channel;
        channel.onMessage = (msg) => _onData(sid, msg);
      };
      final sdp = (p['sdp'] as Map).cast<String, dynamic>();
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?));
      s.remoteReady = true;
      await _flushIce(sid);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      _sig?.signal(m.from, 'ranswer', {
        'sid': sid,
        'sdp': {'type': answer.type, 'sdp': answer.sdp},
      });
      if (meta != null) {
        _events.add(RoomUploadStartEvent(_members[m.from]?.alias ?? 'Someone', (meta['name'] as String?) ?? ''));
      }
    } else if (m.kind == 'ranswer') {
      final s = _sessions[sid];
      if (s != null) {
        final sdp = (p['sdp'] as Map).cast<String, dynamic>();
        await s.pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?));
        s.remoteReady = true;
        await _flushIce(sid);
      }
    } else if (m.kind == 'rice') {
      final c = (p['candidate'] as Map?)?.cast<String, dynamic>();
      if (c == null) return;
      final cand = RTCIceCandidate(c['candidate'] as String?, c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt());
      final s = _sessions[sid];
      if (s == null) {
        // Candidate raced ahead of its roffer (the session is still awaiting
        // the ICE-server fetch) — hold it; the roffer handler adopts it.
        final held = _earlyIce.putIfAbsent(sid, () => []);
        if (held.length < _earlyIceMax) held.add(cand);
        return;
      }
      if (s.remoteReady) {
        await s.pc.addCandidate(cand);
      } else {
        s.pendingIce.add(cand);
      }
    }
  }

  Future<void> _flushIce(String sid) async {
    final s = _sessions[sid];
    if (s == null) return;
    for (final c in s.pendingIce) {
      await s.pc.addCandidate(c);
    }
    s.pendingIce.clear();
  }

  Future<RTCPeerConnection> _newPc(String sid, String peerId) async {
    final ice = await fetchWebrtcIceServers();
    if (kDebugMode) {
      final hasTurn = ice.any((s) => '${s['urls']}'.contains('turn'));
      debugPrint('[wrtc-room] $sid pc: ice servers=${ice.length} turn=$hasTurn');
    }
    final pc = await createPeerConnection({'iceServers': ice});
    pc.onIceCandidate = (c) {
      _sig?.signal(peerId, 'rice', {'sid': sid, 'candidate': c.toMap()});
    };
    pc.onIceConnectionState = (state) {
      if (kDebugMode) debugPrint('[wrtc-room] $sid iceState: $state');
    };
    pc.onConnectionState = (state) {
      if (kDebugMode) debugPrint('[wrtc-room] $sid pcState: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        final s = _sessions[sid];
        // A receive that dies mid-flight would otherwise leave the "uploading…"
        // banner spinning forever — clear it honestly.
        if (s != null && s.role == 'recv' && s.meta != null) {
          _events.add(const RoomUploadDoneEvent());
        }
        _teardown(sid);
      }
    };
    return pc;
  }

  // ── receiver: assemble chunks, save to disk, surface as a room file ──
  void _onData(String sid, RTCDataChannelMessage msg) {
    final s = _sessions[sid];
    if (s == null || !msg.isBinary || s.sink == null) return;
    final bytes = msg.binary;
    if (kDebugMode && s.received == 0) {
      debugPrint('[wrtc-room] $sid first chunk (${bytes.length}B)');
    }
    s.sink!.add(bytes);
    s.received += bytes.length;
    final total = (s.meta?['size'] as num?)?.toInt() ?? 0;
    if (total > 0 && s.received >= total) unawaited(_finishReceive(sid));
  }

  Future<IOSink> _openOutput(_Session s) async {
    final name = (s.meta?['name'] as String?) ?? 'file';
    final target = await _uniquePath(name);
    s.outFile = target;
    return target.openWrite();
  }

  Future<void> _finishReceive(String sid) async {
    final s = _sessions[sid];
    if (s == null || s.outFile == null) return;
    if (kDebugMode) debugPrint('[wrtc-room] $sid receive complete (${s.received}B)');
    try {
      await s.sink?.flush();
      await s.sink?.close();
    } catch (e) {
      // The bytes never made it to disk — clear the banner and stop; claiming
      // "file added" for a file that doesn't exist would be a lie.
      if (kDebugMode) debugPrint('[wrtc-room] $sid save FAILED: $e');
      _events.add(const RoomUploadDoneEvent());
      _teardown(sid);
      return;
    }
    final name = (s.meta?['name'] as String?) ?? s.outFile!.uri.pathSegments.last;
    final mime = (s.meta?['mime'] as String?) ?? 'application/octet-stream';
    final size = (s.meta?['size'] as num?)?.toInt() ?? await s.outFile!.length();
    final alias = _members[s.peerId]?.alias ?? 'Web';
    _savedPaths[sid] = s.outFile!.path;
    try {
      await _history.recordReceived(ReceivedFile(
        fileName: s.outFile!.uri.pathSegments.last,
        savedPath: s.outFile!.path,
        size: size,
        senderAlias: alias,
        receivedAt: DateTime.now(),
        verified: false,
        fileType: mime,
      ));
    } catch (_) {/* history best-effort */}
    _events.add(RoomFileAddedEvent(RoomFile(
      id: sid,
      fileName: name,
      fileType: mime,
      size: size,
      ownerFingerprint: s.peerId,
      ownerAlias: alias,
    )));
    _events.add(const RoomUploadDoneEvent());
    _teardown(sid);
  }

  Future<File> _uniquePath(String fileName) async {
    final dir = _server.saveDirectory;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    // dir.path, NOT '$dir' — interpolating the Directory object bakes
    // "Directory: '/…'" into the path, so every received room file was written
    // to a garbage location (and downstream consumers crashed opening it).
    final dirPath = dir.path;
    final safe = fileName.replaceAll(RegExp(r'[/\\]'), '_');
    var target = File('$dirPath${Platform.pathSeparator}$safe');
    var i = 1;
    final dot = safe.lastIndexOf('.');
    final base = dot > 0 ? safe.substring(0, dot) : safe;
    final ext = dot > 0 ? safe.substring(dot) : '';
    while (await target.exists()) {
      target = File('$dirPath${Platform.pathSeparator}$base ($i)$ext');
      i++;
    }
    return target;
  }

  void _teardown(String sid) {
    _earlyIce.remove(sid);
    final s = _sessions.remove(sid);
    if (s == null) return;
    try {
      s.dc?.close();
      s.pc.close();
    } catch (_) {/* noop */}
    if (s.received < ((s.meta?['size'] as num?)?.toInt() ?? 0)) {
      s.sink?.close().catchError((_) {});
    }
  }

  Future<void> leave() async {
    for (final sid in _sessions.keys.toList()) {
      _teardown(sid);
    }
    _members.clear();
    _savedPaths.clear();
    _sig?.close();
    _sig = null;
  }

  void dispose() {
    leave();
    _events.close();
  }
}
