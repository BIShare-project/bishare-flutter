import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';
import 'package:dio/dio.dart' as dio;
import 'package:flutter/foundation.dart' show compute;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../core/constants/cloud.dart' show ShareCodes;
import '../../../core/constants/protocol.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/telemetry/telemetry_service.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';
import '../domain/room_models.dart';
import 'room_service.dart'
    show
        RoomEvent,
        RoomMemberJoinedEvent,
        RoomMemberLeftEvent,
        RoomFileAddedEvent,
        RoomClosedEvent;

/// Local (same-Wi-Fi) transfer rooms over Bonjour + HTTP on port 58319 — no
/// relay/internet. Byte-for-byte compatible with the native `RoomService` local
/// protocol: each participant advertises/browses `_bishare-room._tcp` and runs
/// an HTTP server; the host fans out member/file events to peers, members poll
/// the host for liveness, and files are pulled directly from their owner.
///
/// Emits the same [RoomEvent]s as the remote [RoomService] so the cubit/UI are
/// shared.
class LocalRoomService {
  LocalRoomService(this._identity, this._server, this._history, this._telemetry);

  final DeviceIdentity _identity;
  final TransferServer _server;
  final HistoryRepository _history;
  final TelemetryService _telemetry;
  final dio.Dio _dio =
      dio.Dio(dio.BaseOptions(connectTimeout: const Duration(seconds: 6)));

  final StreamController<RoomEvent> _events =
      StreamController<RoomEvent>.broadcast();
  Stream<RoomEvent> get events => _events.stream;

  HttpServer? _http;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _discoverySub;
  Timer? _pollTimer;

  String _code = '';
  bool _isHost = false;
  String _hostAlias = '';
  String _hostFingerprint = '';

  final List<RoomMember> _members = [];
  final List<RoomFile> _files = [];
  final Map<String, String> _fileStorage = {}; // fileId -> my local file path
  // fingerprint -> host:port for everyone we can reach (host + members).
  final Map<String, ({String host, int port})> _endpoints = {};

  int get _port => BISharePort.room;

  // ---- Host: create ----

  Future<RoomSession> createLocal() async {
    _code = _generateCode();
    _isHost = true;
    _hostAlias = _identity.alias;
    _hostFingerprint = _identity.fingerprint;
    await _startServer();
    final ip = await LocalIp.resolve();
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'room-$_code',
        type: BIShareService.room,
        port: _port,
        attributes: {
          'roomCode': _code,
          'hostAlias': _hostAlias,
          'hostFingerprint': _hostFingerprint,
          'hostIP': ip,
        },
      ),
    );
    await _broadcast!.initialize();
    await _broadcast!.start();
    // Anonymous, opt-out telemetry: a local (LAN) room never touches the relay,
    // so report it once here so it shows up in the public stats. Fire-and-forget.
    _telemetry.recordLocalRoom();
    return RoomSession(
      code: _code,
      hostFingerprint: _hostFingerprint,
      hostAlias: _hostAlias,
      isHost: true,
      remote: false,
    );
  }

  // ---- Member: join ----

  /// Browse for `room-<code>` and join it. Returns null if no local room with
  /// that code appears within [timeout] (the caller can then try remote).
  Future<(RoomSession, List<RoomMember>, List<RoomFile>)?> joinLocal(
    String code, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    // Per-call locals: the join race abandons the losing realm with an unawaited
    // joinLocal, so a still-running search must NEVER tear down a LATER call's
    // discovery via shared fields. This call owns its discovery + subscription +
    // target code; the shared fields exist only for dispose()'s force-stop and
    // are cleared identity-guarded (see [_stopJoinDiscovery]).
    final targetCode = code.toUpperCase();
    final found = Completer<BonsoirService?>();
    final discovery = BonsoirDiscovery(type: BIShareService.room);
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    try {
      await discovery.initialize();
      sub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            if (service.name == 'room-$targetCode') {
              discovery.serviceResolver.resolveService(service);
            }
          case BonsoirDiscoveryServiceResolvedEvent(:final service):
            if (service.name == 'room-$targetCode' && !found.isCompleted) {
              found.complete(service);
            }
          default:
            break;
        }
      });
      _discovery = discovery;
      _discoverySub = sub;
      await discovery.start();

      final service =
          await found.future.timeout(timeout, onTimeout: () => null);
      await _stopJoinDiscovery(discovery, sub);
      if (service == null) return null; // no local room — caller falls back

    _code = targetCode;
    final attrs = service.attributes;
    final hostIp = attrs['hostIP'] ??
        (service.hostAddresses.isNotEmpty ? service.hostAddresses.first : '');
    _hostAlias = attrs['hostAlias'] ?? '';
    _hostFingerprint = attrs['hostFingerprint'] ?? '';
    if (hostIp.isEmpty) return null;

    _isHost = false;
    _endpoints[_hostFingerprint] = (host: hostIp, port: _port);

    // Start our own server first so the host/peers can reach us for fan-out.
    await _startServer();
    final myIp = await LocalIp.resolve();

    final res = await _dio.postUri<String>(
      Uri.parse(
        'http://$hostIp:$_port${BIShareApi.roomJoin}'
        '?alias=${Uri.encodeComponent(_identity.alias)}'
        '&fingerprint=${_identity.fingerprint}'
        '&host=$myIp&port=$_port&deviceType=${_identity.deviceType}',
      ),
      options: dio.Options(responseType: dio.ResponseType.plain),
    );
    // The join response embeds every shared file's base64 thumbnail, so the
    // payload can be large. Decode it on a background isolate to keep the UI
    // thread free while the cubit is showing the connecting spinner.
    final raw = res.data;
    final body = _asMap(
      raw == null || raw.isEmpty
          ? const <String, dynamic>{}
          : await compute<String, dynamic>(jsonDecode, raw),
    );
    final members = [
      for (final m in (body['members'] as List? ?? []))
        RoomMember.fromJson((m as Map).cast<String, dynamic>()),
    ];
    final files = [
      for (final f in (body['files'] as List? ?? []))
        RoomFile.fromJson((f as Map).cast<String, dynamic>()),
    ];
    _members
      ..clear()
      ..addAll(members.where((m) => m.fingerprint != _identity.fingerprint));
    _files
      ..clear()
      ..addAll(files);
    for (final m in _members) {
      if (m.host.isNotEmpty) _endpoints[m.fingerprint] = (host: m.host, port: m.port);
    }
    _startPolling(hostIp);
    return (
      RoomSession(
        code: _code,
        hostFingerprint: _hostFingerprint,
        hostAlias: _hostAlias,
        isHost: false,
        remote: false,
      ),
      _members.toList(),
      _files.toList(),
    );
    } on Object {
      // Local join failed (Bonjour unavailable / host unreachable) — clean up
      // and let the caller fall back to a remote room.
      await _stopJoinDiscovery(discovery, sub);
      _teardown();
      return null;
    }
  }

  /// Stops THIS join call's discovery + subscription, then clears the shared
  /// fields only if they still point at these objects — a concurrent joinLocal
  /// may have replaced them with its own, which must be left running. Idempotent.
  Future<void> _stopJoinDiscovery(
    BonsoirDiscovery discovery,
    StreamSubscription<BonsoirDiscoveryEvent>? sub,
  ) async {
    try {
      await sub?.cancel();
    } on Object catch (_) {}
    try {
      await discovery.stop();
    } on Object catch (_) {}
    if (identical(_discoverySub, sub)) _discoverySub = null;
    if (identical(_discovery, discovery)) _discovery = null;
  }

  // ---- Server (both host + members run it) ----

  Future<void> _startServer() async {
    final router = Router()
      ..get(BIShareApi.roomInfo, _handleInfo)
      ..post(BIShareApi.roomJoin, _handleJoin)
      ..get(BIShareApi.roomFiles, _handleFiles)
      ..get(BIShareApi.roomDownload, _handleDownload)
      ..post(BIShareApi.roomFileAdded, _handleFileAdded)
      ..post(BIShareApi.roomKicked, _handleKicked)
      ..post(BIShareApi.roomMemberLeft, _handleMemberLeft)
      ..post(BIShareApi.roomMemberJoined, _handleMemberJoined);
    _http = await shelf_io.serve(
      router.call,
      InternetAddress.anyIPv4,
      _port,
      shared: true,
    );
  }

  Response _handleInfo(Request req) => Response.ok(
    jsonEncode({
      'code': _code,
      'hostAlias': _hostAlias,
      'hostFingerprint': _hostFingerprint,
      'memberCount': _members.length,
      'fileCount': _files.length,
    }),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> _handleJoin(Request req) async {
    final q = req.url.queryParameters;
    final fingerprint = q['fingerprint'];
    final alias = q['alias'];
    final host = q['host'];
    if (fingerprint == null || alias == null || host == null) {
      return Response(400, body: '{"error":"missing params"}');
    }
    final member = RoomMember(
      fingerprint: fingerprint,
      alias: alias,
      deviceType: q['deviceType'] ?? 'mobile',
      host: host,
      port: int.tryParse(q['port'] ?? '') ?? _port,
    );
    if (!_members.any((m) => m.fingerprint == fingerprint)) {
      _members.add(member);
      _endpoints[fingerprint] = (host: host, port: member.port);
      _events.add(RoomMemberJoinedEvent(member));
      // Fan out the new member to the other members we know.
      final payload = jsonEncode({
        'fingerprint': fingerprint,
        'alias': alias,
        'deviceType': member.deviceType,
        'host': host,
        'port': member.port,
      });
      for (final m in _members) {
        if (m.fingerprint == fingerprint || m.host.isEmpty) continue;
        _post(m.host, m.port, BIShareApi.roomMemberJoined, payload);
      }
    }
    return Response.ok(
      jsonEncode({
        'members': [
          for (final m in _members)
            {
              'fingerprint': m.fingerprint,
              'alias': m.alias,
              'deviceType': m.deviceType,
              'host': m.host,
              'port': m.port,
            },
        ],
        'files': _files.map(_fileJson).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleFiles(Request req) => Response.ok(
    jsonEncode(_files.map(_fileJson).toList()),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> _handleDownload(Request req) async {
    final id = req.url.queryParameters['fileId'];
    final path = id == null ? null : _fileStorage[id];
    if (path == null || !File(path).existsSync()) {
      return Response.notFound('{"error":"file not found"}');
    }
    final file = File(path);
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '${file.lengthSync()}',
      },
    );
  }

  Future<Response> _handleFileAdded(Request req) async {
    final body = _asMap(jsonDecode(await req.readAsString()));
    final file = RoomFile.fromJson(body);
    final idx = _files.indexWhere((f) => f.id == file.id);
    if (idx < 0) {
      _files.add(file);
      _events.add(RoomFileAddedEvent(file));
    } else if (file.thumbnail != null && _files[idx].thumbnail == null) {
      _files[idx] = file;
      _events.add(RoomFileAddedEvent(file));
    }
    return Response.ok('{"ok":true}');
  }

  Response _handleKicked(Request req) {
    _events.add(const RoomClosedEvent());
    _teardown();
    return Response.ok('{"ok":true}');
  }

  Future<Response> _handleMemberLeft(Request req) async {
    final body = _asMap(jsonDecode(await req.readAsString()));
    final fp = body['fingerprint'] as String?;
    if (fp != null) {
      _members.removeWhere((m) => m.fingerprint == fp);
      _endpoints.remove(fp);
      _events.add(RoomMemberLeftEvent(fp));
    }
    return Response.ok('{"ok":true}');
  }

  Future<Response> _handleMemberJoined(Request req) async {
    final body = _asMap(jsonDecode(await req.readAsString()));
    final fp = body['fingerprint'] as String?;
    if (fp != null &&
        fp != _identity.fingerprint &&
        !_members.any((m) => m.fingerprint == fp)) {
      final member = RoomMember.fromJson(body);
      _members.add(member);
      if (member.host.isNotEmpty) {
        _endpoints[fp] = (host: member.host, port: member.port);
      }
      _events.add(RoomMemberJoinedEvent(member));
    }
    return Response.ok('{"ok":true}');
  }

  // ---- Add / download files ----

  /// Share a local file into the room: store it, add it to our list, and
  /// broadcast `file-added` to the host + every member.
  Future<void> addFile(
    File file, {
    required String name,
    required String mime,
    String? thumbnailBase64,
  }) async {
    final id = _generateId();
    _fileStorage[id] = file.path;
    final room = RoomFile(
      id: id,
      fileName: name,
      fileType: mime,
      size: await file.length(),
      ownerFingerprint: _identity.fingerprint,
      ownerAlias: _identity.alias,
      thumbnail: thumbnailBase64,
    );
    _files.add(room);
    _events.add(RoomFileAddedEvent(room));
    final payload = jsonEncode(_fileJson(room));
    for (final e in _endpoints.entries) {
      _post(e.value.host, e.value.port, BIShareApi.roomFileAdded, payload);
    }
  }

  /// Download a shared file from its owner and record it in the Inbox.
  Future<File> downloadFile(RoomFile file) async {
    final ep = _endpoints[file.ownerFingerprint];
    if (ep == null) {
      throw const _LocalRoomException('That device is no longer reachable.');
    }
    final target = await _uniquePath(file.fileName);
    await _dio.downloadUri(
      Uri.parse('http://${ep.host}:${ep.port}${BIShareApi.roomDownload}?fileId=${file.id}'),
      target.path,
    );
    try {
      await _history.recordReceived(
        ReceivedFile(
          fileName: target.uri.pathSegments.last,
          savedPath: target.path,
          size: await target.length(),
          senderAlias: file.ownerAlias,
          receivedAt: DateTime.now(),
          verified: false,
          fileType: file.fileType,
        ),
      );
    } on Object {
      // downloaded fine; just not recorded
    }
    return target;
  }

  /// Same as [downloadFile] but to a temp path (for previewing).
  Future<File> downloadToTemp(RoomFile file) async {
    final ep = _endpoints[file.ownerFingerprint];
    if (ep == null) {
      throw const _LocalRoomException('That device is no longer reachable.');
    }
    final safe = file.fileName.split(RegExp(r'[/\\]')).last;
    final target = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}bishare-room-${DateTime.now().microsecondsSinceEpoch}-$safe',
    );
    await _dio.downloadUri(
      Uri.parse('http://${ep.host}:${ep.port}${BIShareApi.roomDownload}?fileId=${file.id}'),
      target.path,
    );
    return target;
  }

  // ---- Liveness + leave ----

  void _startPolling(String hostIp) {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await _dio.getUri<dynamic>(
          Uri.parse('http://$hostIp:$_port${BIShareApi.roomInfo}'),
        );
      } on Object {
        // host unreachable → room closed
        _events.add(const RoomClosedEvent());
        _teardown();
      }
    });
  }

  Future<void> leave() async {
    if (_isHost) {
      // Tell everyone the room is closing.
      final me = _identity.fingerprint;
      for (final e in _endpoints.entries) {
        if (e.key == me) continue;
        _post(e.value.host, e.value.port, BIShareApi.roomKicked, '');
      }
    } else {
      final payload = jsonEncode({'fingerprint': _identity.fingerprint});
      final host = _endpoints[_hostFingerprint];
      if (host != null) {
        await _postAwait(host.host, host.port, BIShareApi.roomMemberLeft, payload);
      }
    }
    _teardown();
  }

  void _teardown() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _discoverySub?.cancel();
    _discovery?.stop();
    _discovery = null;
    _broadcast?.stop();
    _broadcast = null;
    _http?.close(force: true);
    _http = null;
    _members.clear();
    _files.clear();
    _fileStorage.clear();
    _endpoints.clear();
  }

  // ---- helpers ----

  Map<String, dynamic> _fileJson(RoomFile f) => {
    'id': f.id,
    'fileName': f.fileName,
    'fileType': f.fileType,
    'size': f.size,
    'ownerAlias': f.ownerAlias,
    'ownerFingerprint': f.ownerFingerprint,
    'addedAt': DateTime.now().toUtc().toIso8601String(),
    if (f.thumbnail != null) 'thumbnail': f.thumbnail,
  };

  void _post(String host, int port, String path, String body) {
    _dio
        .postUri<dynamic>(
          Uri.parse('http://$host:$port$path'),
          data: body,
          options: dio.Options(contentType: 'application/json'),
        )
        .ignore();
  }

  Future<void> _postAwait(String host, int port, String path, String body) async {
    try {
      await _dio.postUri<dynamic>(
        Uri.parse('http://$host:$port$path'),
        data: body,
        options: dio.Options(contentType: 'application/json'),
      );
    } on Object {
      // best effort
    }
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  String _generateCode() {
    final rand = Random.secure();
    return List.generate(
      ShareCodes.roomLength,
      (_) => ShareCodes.roomCharset[rand.nextInt(ShareCodes.roomCharset.length)],
    ).join();
  }

  String _generateId() {
    final rand = Random.secure();
    return List.generate(
      16,
      (_) => ShareCodes.roomCharset[rand.nextInt(ShareCodes.roomCharset.length)],
    ).join();
  }

  Future<File> _uniquePath(String fileName) async {
    final dir = _server.saveDirectory;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final safe = fileName.split(RegExp(r'[/\\]')).last.trim();
    final base = safe.isEmpty ? 'file' : safe;
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    final ext = dot > 0 ? base.substring(dot) : '';
    var candidate = base;
    var n = 1;
    while (true) {
      final file = File('${dir.path}${Platform.pathSeparator}$candidate');
      try {
        file.createSync(exclusive: true);
        return file;
      } on FileSystemException {
        candidate = '$stem ($n)$ext';
        n++;
      }
    }
  }
}

class _LocalRoomException implements Exception {
  const _LocalRoomException(this.message);
  final String message;
  @override
  String toString() => message;
}
