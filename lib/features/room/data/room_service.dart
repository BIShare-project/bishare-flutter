import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../../core/constants/cloud.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';
import '../domain/room_models.dart';

/// A live room event pushed over the WebSocket (presence + broadcasts).
sealed class RoomEvent {
  const RoomEvent();
}

class RoomSyncEvent extends RoomEvent {
  const RoomSyncEvent(this.info, this.members, this.files);
  final RoomInfo? info;
  final List<RoomMember> members;
  final List<RoomFile> files;
}

class RoomMemberJoinedEvent extends RoomEvent {
  const RoomMemberJoinedEvent(this.member);
  final RoomMember member;
}

class RoomMemberLeftEvent extends RoomEvent {
  const RoomMemberLeftEvent(this.fingerprint);
  final String fingerprint;
}

class RoomFileAddedEvent extends RoomEvent {
  const RoomFileAddedEvent(this.file);
  final RoomFile file;
}

class RoomUploadStartEvent extends RoomEvent {
  const RoomUploadStartEvent(this.alias, this.fileName);
  final String alias;
  final String fileName;
}

class RoomUploadDoneEvent extends RoomEvent {
  const RoomUploadDoneEvent();
}

class RoomClosedEvent extends RoomEvent {
  const RoomClosedEvent();
}

/// Remote transfer rooms over the relay (REST + WebSocket). Grounded to the
/// Cloudflare Workers room Durable Object. Local (Bonjour 58319) rooms are a
/// later batch.
class RoomService {
  RoomService(this._identity, this._server, this._history);

  final DeviceIdentity _identity;
  final TransferServer _server;
  final HistoryRepository _history;
  final Dio _dio = Dio(BaseOptions(receiveTimeout: Duration.zero));

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  String? _code;
  bool _active = false;

  final StreamController<RoomEvent> _events =
      StreamController<RoomEvent>.broadcast();
  Stream<RoomEvent> get events => _events.stream;

  Uri _api(String path) => Uri.parse('${CloudConfig.apiBase}$path');

  Map<String, dynamic>? _data(Response<dynamic> res) {
    final body = res.data;
    if (body is Map && body['data'] is Map) {
      return (body['data'] as Map).cast<String, dynamic>();
    }
    if (body is Map) return body.cast<String, dynamic>();
    return null;
  }

  /// Create a new remote room; returns our host session (keep the hostToken).
  Future<RoomSession> createRemote() async {
    final res = await _dio.postUri<dynamic>(
      _api(CloudConfig.rooms),
      data: {'fingerprint': _identity.fingerprint, 'alias': _identity.alias},
    );
    final d = _data(res)!;
    final code = d['code'] as String;
    _connectWs(code);
    return RoomSession(
      code: code,
      hostFingerprint: _identity.fingerprint,
      hostAlias: _identity.alias,
      isHost: true,
      hostToken: d['hostToken'] as String?,
    );
  }

  /// Join an existing remote room by code.
  Future<(RoomSession, List<RoomMember>, List<RoomFile>)> joinRemote(
    String code,
  ) async {
    final res = await _dio.postUri<String>(
      _api(CloudConfig.roomJoin(code)),
      data: {
        'fingerprint': _identity.fingerprint,
        'alias': _identity.alias,
        'deviceType': _identity.deviceType,
      },
      options: Options(responseType: ResponseType.plain),
    );
    // The join response carries the room's file list with base64 thumbnails, so
    // decode it off the UI isolate to keep the connecting spinner smooth.
    final raw = res.data;
    final decoded = raw == null || raw.isEmpty
        ? const <String, dynamic>{}
        : await compute<String, dynamic>(jsonDecode, raw);
    final body = decoded is Map
        ? decoded.cast<String, dynamic>()
        : const <String, dynamic>{};
    final d = (body['data'] is Map ? body['data'] as Map : body)
        .cast<String, dynamic>();
    final room = (d['room'] as Map).cast<String, dynamic>();
    final members = [
      for (final m in (d['members'] as List? ?? []))
        RoomMember.fromJson((m as Map).cast<String, dynamic>()),
    ];
    final files = [
      for (final f in (d['files'] as List? ?? []))
        RoomFile.fromJson((f as Map).cast<String, dynamic>()),
    ];
    final hostFp = room['hostFingerprint'] as String? ?? '';
    _connectWs(code);
    return (
      RoomSession(
        code: code,
        hostFingerprint: hostFp,
        hostAlias: room['hostAlias'] as String? ?? '',
        isHost: hostFp == _identity.fingerprint,
      ),
      members,
      files,
    );
  }

  void _connectWs(String code) {
    _code = code;
    _active = true;
    _openSocket();
  }

  void _openSocket() {
    if (!_active || _code == null) return;
    // Tear down any prior socket so reconnects don't stack subscriptions.
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close(ws_status.normalClosure);
    _ws = null;
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('${CloudConfig.wsBase}${CloudConfig.roomWs(_code!)}'),
      );
      _ws = channel;
      channel.sink.add(
        jsonEncode({
          'type': 'join',
          'data': {
            'fingerprint': _identity.fingerprint,
            'alias': _identity.alias,
            'deviceType': _identity.deviceType,
          },
        }),
      );
      _wsSub = channel.stream.listen(
        _onWsMessage,
        onDone: _onWsClosed,
        onError: (_) => _onWsClosed(),
        cancelOnError: true,
      );
    } on Object {
      _onWsClosed();
    }
  }

  void _onWsMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on Object {
      return;
    }
    final data = msg['data'];
    final map = data is Map ? data.cast<String, dynamic>() : const <String, dynamic>{};
    switch (msg['type']) {
      case 'sync':
        _events.add(
          RoomSyncEvent(
            map['info'] is Map
                ? RoomInfo.fromJson((map['info'] as Map).cast<String, dynamic>())
                : null,
            [
              for (final m in (map['members'] as List? ?? []))
                RoomMember.fromJson((m as Map).cast<String, dynamic>()),
            ],
            [
              for (final f in (map['files'] as List? ?? []))
                RoomFile.fromJson((f as Map).cast<String, dynamic>()),
            ],
          ),
        );
      case 'member_joined':
        _events.add(RoomMemberJoinedEvent(RoomMember.fromJson(map)));
      case 'member_left':
        _events.add(RoomMemberLeftEvent(map['fingerprint'] as String? ?? ''));
      case 'file_added':
        if (map['file'] is Map) {
          _events.add(
            RoomFileAddedEvent(
              RoomFile.fromJson((map['file'] as Map).cast<String, dynamic>()),
            ),
          );
        }
      case 'upload_start':
        _events.add(
          RoomUploadStartEvent(
            map['alias'] as String? ?? '',
            map['fileName'] as String? ?? '',
          ),
        );
      case 'upload_done':
        _events.add(const RoomUploadDoneEvent());
      case 'room_closed':
        _events.add(const RoomClosedEvent());
    }
  }

  void _onWsClosed() {
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    // Reconnect while we're still in the room (mirrors native's 3s retry).
    if (_active) {
      Future.delayed(const Duration(seconds: 3), _openSocket);
    }
  }

  /// Upload [file] into the room (raw body + metadata headers).
  Future<RoomFile> uploadFile(
    String code,
    File file, {
    required String fileName,
    required String mimeType,
    String? thumbnailBase64,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final length = await file.length();
    final headers = <String, dynamic>{
      'X-File-Name': fileName,
      'X-File-Type': mimeType,
      'X-Owner-Fingerprint': _identity.fingerprint,
      'X-Owner-Alias': _identity.alias,
      Headers.contentLengthHeader: length,
    };
    if (thumbnailBase64 != null) headers['X-Thumbnail'] = thumbnailBase64;
    final res = await _dio.postUri<dynamic>(
      _api(CloudConfig.roomFiles(code)),
      data: file.openRead(),
      options: Options(
        headers: headers,
        contentType: 'application/octet-stream',
      ),
      onSendProgress: onProgress,
      cancelToken: cancel,
    );
    return RoomFile.fromJson(_data(res)!);
  }

  /// Download a room file to the save directory + record it in the Inbox.
  Future<File> downloadFile(
    String code,
    RoomFile file, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final target = await _uniquePath(file.fileName);
    await _dio.downloadUri(
      _api(CloudConfig.roomFile(code, file.id)),
      target.path,
      onReceiveProgress: onProgress,
      cancelToken: cancel,
    );
    // The bytes are on disk now — record to the Inbox best-effort so a DB hiccup
    // never turns a successful download into a reported failure.
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

  /// Download a room file to a temp path (for previewing) without recording it.
  Future<File> downloadToTemp(
    String code,
    RoomFile file, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final dir = Directory.systemTemp;
    final safe = file.fileName.split(RegExp(r'[/\\]')).last;
    final target = File(
      '${dir.path}${Platform.pathSeparator}bishare-room-${DateTime.now().microsecondsSinceEpoch}-$safe',
    );
    await _dio.downloadUri(
      _api(CloudConfig.roomFile(code, file.id)),
      target.path,
      onReceiveProgress: onProgress,
      cancelToken: cancel,
    );
    return target;
  }

  Future<void> leave(String code) async {
    _active = false;
    _disconnect();
    try {
      await _dio.postUri<dynamic>(
        _api(CloudConfig.roomLeave(code)),
        data: {'fingerprint': _identity.fingerprint},
      );
    } on Object {
      // best effort
    }
  }

  Future<void> close(String code, String hostToken) async {
    _active = false;
    _disconnect();
    try {
      await _dio.deleteUri<dynamic>(
        _api(CloudConfig.room(code)),
        options: Options(headers: {'X-Host-Token': hostToken}),
      );
    } on Object {
      // best effort
    }
  }

  void _disconnect() {
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close(ws_status.normalClosure);
    _ws = null;
    _code = null;
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
        file.createSync(exclusive: true); // atomic reserve (TOCTOU-safe)
        return file;
      } on FileSystemException {
        candidate = '$stem ($n)$ext';
        n++;
      }
    }
  }
}
