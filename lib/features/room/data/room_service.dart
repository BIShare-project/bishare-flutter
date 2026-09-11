import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../../../core/constants/cloud.dart';
import '../../../core/crypto/bse2.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/io/scratch_dir.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';
import '../domain/room_models.dart';
import 'room_e2e.dart';

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

/// The room's encryption state changed (e.g. the key arrived).
class RoomSecurityEvent extends RoomEvent {
  const RoomSecurityEvent(this.security);
  final RoomSecurity security;
}

/// Files whose sealed metadata the room key just opened — replace by id.
class RoomFilesRevealedEvent extends RoomEvent {
  const RoomFilesRevealedEvent(this.files);
  final List<RoomFile> files;
}

/// Remote transfer rooms over the relay (REST + WebSocket). Grounded to the
/// Cloudflare Workers room Durable Object. Local (Bonjour 58319) rooms are a
/// later batch.
///
/// Rooms this app creates are end-to-end encrypted (see `room_e2e.dart`):
/// the room key is made here, handed to each member sealed to their X25519
/// key over the WebSocket, files are sealed with BSE2 before upload and
/// opened after download. A room made by an older app stays plaintext and
/// reports [RoomSecurity.plain].
class RoomService {
  RoomService(this._identity, this._server, this._history, this._prefs);

  final DeviceIdentity _identity;
  final TransferServer _server;
  final HistoryRepository _history;
  final SharedPreferences _prefs;
  final Dio _dio = Dio(BaseOptions(receiveTimeout: Duration.zero));

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  String? _code;
  bool _active = false;

  // ── end-to-end encryption state (per joined room) ──
  RoomKeyPair? _pair; // this join's X25519 pair for the hand-off
  Uint8List? _roomKey; // K, once made here or handed to us
  String? _kid; // non-null ⇔ the room is encrypted
  Timer? _keyRetry; // keeps asking while we wait for K
  final Map<String, RoomFile> _files = {}; // as the server sent them, by id
  // WS frames are handled one after another even though opening sealed
  // metadata is async, so a file_added can never overtake its sync.
  Future<void> _inbox = Future.value();

  static const _keyPrefix = 'room_key:';
  static const _keyRetryEvery = Duration(seconds: 8);

  /// Encryption state of the current room.
  RoomSecurity get security => _kid == null
      ? (_code == null ? RoomSecurity.unknown : RoomSecurity.plain)
      : (_roomKey == null ? RoomSecurity.waitingForKey : RoomSecurity.encrypted);

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
  /// The room key is made on this device; the server only learns its kid.
  Future<RoomSession> createRemote() async {
    _resetE2E();
    final key = RoomE2E.newRoomKey();
    final kid = await RoomE2E.keyId(key);
    final res = await _dio.postUri<dynamic>(
      _api(CloudConfig.rooms),
      data: {
        'fingerprint': _identity.fingerprint,
        'alias': _identity.alias,
        'e2e': {'v': RoomE2E.version, 'kid': kid},
      },
    );
    final d = _data(res)!;
    final code = d['code'] as String;
    // Only a server that echoes the kid made an encrypted room; an older one
    // ignores e2e, and sealing files into its plain room would break them.
    if (e2eKidOf(d['e2e']) == kid) {
      _kid = kid;
      _roomKey = key;
      _rememberKey(code, key, kid, d['expiresAt'] as String?);
    }
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
    _resetE2E();
    final res = await _dio.postUri<String>(
      _api(CloudConfig.roomJoin(code)),
      data: {
        'fingerprint': _identity.fingerprint,
        'alias': _identity.alias,
        'deviceType': _identity.deviceType,
        // Lets us into an end-to-end encrypted room (an older app gets 426).
        'e2e': {'v': RoomE2E.version},
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
    final listed = [
      for (final f in (d['files'] as List? ?? []))
        RoomFile.fromJson((f as Map).cast<String, dynamic>()),
    ];
    _kid = e2eKidOf(room['e2e']);
    if (_kid != null) _roomKey = _recallKey(code, _kid!);
    final files = await _revealAll(listed);
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
    _pair = null;
    unawaited(
      RoomE2E.newKeyPair().then((p) {
        _pair = p;
        _openSocket();
      }),
    );
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
            // Whether we need the key is decided after the sync, once the
            // room's kid is known, with an explicit key_request.
            if (_pair != null)
              'e2e': {'v': RoomE2E.version, 'pub': _pair!.publicKeyB64, 'need': false},
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
    _inbox = _inbox.then((_) => _handle(msg)).catchError((Object _) {});
  }

  Future<void> _handle(Map<String, dynamic> msg) async {
    final data = msg['data'];
    final map = data is Map ? data.cast<String, dynamic>() : const <String, dynamic>{};
    switch (msg['type']) {
      case 'sync':
        final info = map['info'] is Map
            ? RoomInfo.fromJson((map['info'] as Map).cast<String, dynamic>())
            : null;
        if (info != null) await _settleKey(info.e2eKid);
        final files = await _revealAll([
          for (final f in (map['files'] as List? ?? []))
            RoomFile.fromJson((f as Map).cast<String, dynamic>()),
        ]);
        _events.add(
          RoomSyncEvent(
            info,
            [
              for (final m in (map['members'] as List? ?? []))
                RoomMember.fromJson((m as Map).cast<String, dynamic>()),
            ],
            files,
          ),
        );
        _events.add(RoomSecurityEvent(security));
      case 'member_joined':
        _events.add(RoomMemberJoinedEvent(RoomMember.fromJson(map)));
      case 'member_left':
        _events.add(RoomMemberLeftEvent(map['fingerprint'] as String? ?? ''));
      case 'file_added':
        if (map['file'] is Map) {
          final f = await _reveal(
            RoomFile.fromJson((map['file'] as Map).cast<String, dynamic>()),
          );
          _events.add(RoomFileAddedEvent(f));
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
        final code = _code;
        if (code != null) _forgetKey(code);
        _events.add(const RoomClosedEvent());
      case 'key_request':
        _answerKeyRequest(map['fingerprint'], map['pub']);
      case 'key_grant':
        await _acceptKeyGrant(map['pub'], map['box']);
    }
  }

  // ── end-to-end encryption ────────────────────────────────────────────────

  void _resetE2E() {
    _keyRetry?.cancel();
    _keyRetry = null;
    _roomKey = null;
    _kid = null;
    _files.clear();
  }

  /// After a sync: is the room encrypted, and do we hold its key? A key held
  /// or stored for this code counts only if its kid matches.
  Future<void> _settleKey(String? kid) async {
    _kid = kid;
    if (kid == null) {
      _roomKey = null;
      return;
    }
    final held = _roomKey;
    if (held != null && await RoomE2E.keyId(held) == kid) return;
    _roomKey = _code == null ? null : _recallKey(_code!, kid);
    if (_roomKey == null) _askForKey();
  }

  void _askForKey() {
    _send('key_request', const {});
    _keyRetry ??= Timer.periodic(_keyRetryEvery, (_) {
      if (!_active || _roomKey != null || _kid == null) {
        _keyRetry?.cancel();
        _keyRetry = null;
        return;
      }
      _send('key_request', const {});
    });
  }

  /// Someone without the key asked; anyone who holds it answers after a short
  /// random delay (the asker keeps the first good answer).
  void _answerKeyRequest(Object? fingerprint, Object? pub) {
    final key = _roomKey;
    final pair = _pair;
    final code = _code;
    if (key == null || pair == null || code == null || _kid == null) return;
    if (fingerprint is! String || pub is! String || fingerprint == _identity.fingerprint) return;
    Future.delayed(Duration(milliseconds: Random().nextInt(400)), () async {
      try {
        final box = await RoomE2E.grant(key, code, pair, pub);
        _send('key_grant', {'to': fingerprint, 'box': box});
      } on Object {
        // a malformed key from the asker — nothing to hand over
      }
    });
  }

  Future<void> _acceptKeyGrant(Object? pub, Object? box) async {
    final kid = _kid;
    final pair = _pair;
    final code = _code;
    if (_roomKey != null || kid == null || pair == null || code == null) return;
    if (pub is! String || box is! String) return;
    final Uint8List key;
    try {
      key = await RoomE2E.acceptGrant(code, pair, pub, box, kid);
    } on Object {
      return; // doesn't open, or isn't this room's key — wait for another
    }
    if (_roomKey != null || _kid != kid) return;
    _roomKey = key;
    _keyRetry?.cancel();
    _keyRetry = null;
    _rememberKey(code, key, kid, null);
    _events.add(RoomSecurityEvent(security));
    final revealed = await _revealAll(_files.values.toList());
    _events.add(RoomFilesRevealedEvent(revealed));
  }

  Future<RoomFile> _reveal(RoomFile f) async {
    _files[f.id] = f;
    final enc = f.enc;
    final key = _roomKey;
    if (enc == null || key == null) return f;
    try {
      final opened = await RoomE2E.openFile(key, enc.salt, enc.meta);
      return f.reveal(
        name: opened.meta.name,
        type: opened.meta.type,
        plainSize: opened.meta.size,
        preview: opened.meta.thumbnail,
      );
    } on RoomKeyException {
      return f; // stays sealed in the list
    }
  }

  Future<List<RoomFile>> _revealAll(List<RoomFile> files) async {
    _files.clear();
    return [for (final f in files) await _reveal(f)];
  }

  void _send(String type, Map<String, dynamic> data) {
    try {
      _ws?.sink.add(jsonEncode({'type': type, 'data': data}));
    } on Object {
      // socket going down; the retry timer covers a lost request
    }
  }

  // K survives an app restart for the room's lifetime: otherwise a host alone
  // in the room would have nobody to ask for it again.
  void _rememberKey(String code, Uint8List key, String kid, String? expiresAt) {
    final exp = expiresAt ??
        DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
    unawaited(_prefs.setString(
      '$_keyPrefix$code',
      jsonEncode({'k': RoomE2E.b64u(key), 'kid': kid, 'exp': exp}),
    ));
  }

  Uint8List? _recallKey(String code, String kid) {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_keyPrefix)).toList()) {
      try {
        final v = jsonDecode(_prefs.getString(k) ?? '{}') as Map;
        final exp = v['exp'];
        if (exp is! String || exp.compareTo(now) < 0) unawaited(_prefs.remove(k));
      } on Object {
        unawaited(_prefs.remove(k));
      }
    }
    try {
      final v = jsonDecode(_prefs.getString('$_keyPrefix$code') ?? '') as Map;
      if (v['kid'] != kid || v['k'] is! String) return null;
      return RoomE2E.fromB64u(v['k'] as String);
    } on Object {
      return null;
    }
  }

  void _forgetKey(String code) => unawaited(_prefs.remove('$_keyPrefix$code'));

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
    if (_kid != null) {
      return _uploadSealed(
        code,
        file,
        fileName: fileName,
        mimeType: mimeType,
        thumbnailBase64: thumbnailBase64,
        onProgress: onProgress,
        cancel: cancel,
      );
    }
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

  /// Encrypted room: seal the bytes into a BSE2 scratch file and upload only
  /// that, with the name/type/size/preview sealed into X-Enc-Meta.
  Future<RoomFile> _uploadSealed(
    String code,
    File file, {
    required String fileName,
    required String mimeType,
    String? thumbnailBase64,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final key = _roomKey;
    if (key == null) throw const RoomKeyException('The room key has not arrived yet.');
    final sealed = await RoomE2E.sealFile(
      key,
      RoomFileMeta(
        name: fileName,
        type: mimeType,
        size: await file.length(),
        thumbnail: thumbnailBase64,
      ),
    );
    final scratch = await createScratchDir('bishare-room-');
    try {
      final body = File('${scratch.path}${Platform.pathSeparator}upload.bse2');
      await Bse2.encryptFile(input: file, output: body, key: sealed.fileKey);
      final res = await _dio.postUri<dynamic>(
        _api(CloudConfig.roomFiles(code)),
        data: body.openRead(),
        options: Options(
          headers: {
            'X-File-Name': RoomE2E.sealedName,
            'X-File-Type': 'application/octet-stream',
            'X-Enc-Salt': sealed.salt,
            'X-Enc-Meta': sealed.meta,
            'X-Owner-Fingerprint': _identity.fingerprint,
            'X-Owner-Alias': _identity.alias,
            Headers.contentLengthHeader: await body.length(),
          },
          contentType: 'application/octet-stream',
        ),
        onSendProgress: onProgress,
        cancelToken: cancel,
      );
      return _reveal(RoomFile.fromJson(_data(res)!));
    } finally {
      try {
        await scratch.delete(recursive: true);
      } on Object {
        // temp dir; the OS reclaims it
      }
    }
  }

  /// Fetch [file] into [target], opening it on the way when the room is
  /// encrypted (ciphertext goes to a scratch file, plaintext to [target]).
  Future<void> _fetch(
    String code,
    RoomFile file,
    File target, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final enc = file.enc;
    if (enc == null) {
      await _dio.downloadUri(
        _api(CloudConfig.roomFile(code, file.id)),
        target.path,
        onReceiveProgress: onProgress,
        cancelToken: cancel,
      );
      return;
    }
    final key = _roomKey;
    if (key == null || !file.revealed) {
      throw const RoomKeyException('The room key has not arrived yet.');
    }
    final keys = await RoomE2E.fileKeys(key, RoomE2E.fromB64u(enc.salt));
    final scratch = await createScratchDir('bishare-room-');
    try {
      final sealed = File('${scratch.path}${Platform.pathSeparator}download.bse2');
      await _dio.downloadUri(
        _api(CloudConfig.roomFile(code, file.id)),
        sealed.path,
        onReceiveProgress: onProgress,
        cancelToken: cancel,
      );
      await Bse2.decryptFile(input: sealed, output: target, key: keys.fileKey);
    } finally {
      try {
        await scratch.delete(recursive: true);
      } on Object {
        // temp dir; the OS reclaims it
      }
    }
  }

  /// Download a room file to the save directory + record it in the Inbox.
  Future<File> downloadFile(
    String code,
    RoomFile file, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final target = await _uniquePath(file.fileName);
    try {
      await _fetch(code, file, target, onProgress: onProgress, cancel: cancel);
    } on Object {
      // _uniquePath reserved the name; don't leave an empty file behind.
      try {
        await target.delete();
      } on Object {
        // already gone
      }
      rethrow;
    }
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
    await _fetch(code, file, target, onProgress: onProgress, cancel: cancel);
    return target;
  }

  Future<void> leave(String code) async {
    _active = false;
    _forgetKey(code);
    _resetE2E();
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
    _forgetKey(code);
    _resetE2E();
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
