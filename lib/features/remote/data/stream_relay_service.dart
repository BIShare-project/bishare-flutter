import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';
import 'binary_frame.dart';
import 'cloud_transfer_service.dart' show ProgressCb, CloudDownloadException;

/// Events surfaced while sending over the stream relay (drives the sender UI).
sealed class StreamSendEvent {
  const StreamSendEvent();
}

/// The session code is ready — present `bishare-stream://<code>` as a QR.
class StreamCodeReady extends StreamSendEvent {
  const StreamCodeReady(this.code);
  final String code;
}

/// The receiver connected and accepted; the transfer is now streaming.
class StreamReceiverJoined extends StreamSendEvent {
  const StreamReceiverJoined();
}

class StreamSendProgress extends StreamSendEvent {
  const StreamSendProgress(this.fraction);
  final double fraction;
}

class StreamSendComplete extends StreamSendEvent {
  const StreamSendComplete();
}

class StreamSendFailed extends StreamSendEvent {
  const StreamSendFailed(this.message);
  final String message;
}

/// Zero-storage live transfer through the relay (`wss://…/api/v1/stream`), for
/// peers who can't reach each other on the LAN. Sends/receives the BIShare
/// binary protocol frames, byte-exact with the native `StreamRelayService`.
class StreamRelayService {
  StreamRelayService(this._server, this._history);

  final TransferServer _server;
  final HistoryRepository _history;

  Uri get _wsUri => Uri.parse('${CloudConfig.wsBase}${CloudConfig.stream}');

  // ---- Sender ----

  /// Stream a file to whoever scans the returned code. Emits [StreamCodeReady]
  /// (present the QR), then [StreamReceiverJoined], progress, and completion.
  Stream<StreamSendEvent> send(
    File file, {
    required String fileName,
    required String mimeType,
    required String senderAlias,
  }) async* {
    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    final sha = digest.toString();

    final channel = WebSocketChannel.connect(_wsUri);
    _Conn? conn;
    try {
      await channel.ready;
      conn = _Conn(channel)..start();

      conn.sendText({
        'type': 'create',
        'data': {
          'fileCount': 1,
          'totalSize': size,
          'fileName': fileName,
          'senderAlias': senderAlias,
        },
      });
      final created = await conn.waitText('created', const Duration(seconds: 15));
      yield StreamCodeReady((created['code'] as String?) ?? '');

      await conn.waitText('joined', const Duration(minutes: 10));
      await conn.waitText('accepted', const Duration(seconds: 30));
      yield const StreamReceiverJoined();

      conn.sendBinary(
        encodeJsonFrame(FrameType.fileStart, 0, {
          'fileName': fileName,
          'size': size,
          'fileType': mimeType,
          'sha256': sha,
          'encrypted': false,
        }),
      );

      var sent = 0;
      await for (final chunk in file.openRead()) {
        conn.sendBinary(encodeFrame(FrameType.fileData, 0, chunk));
        sent += chunk.length;
        yield StreamSendProgress(size == 0 ? 1 : sent / size);
      }

      conn.sendBinary(
        encodeJsonFrame(FrameType.fileEnd, 0, {
          'verified': true,
          'encrypted': false,
        }),
      );
      conn.sendBinary(encodeFrame(FrameType.sessionEnd, 0, const []));
      // Give the relay a moment to flush the tail before we tear down.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      yield const StreamSendComplete();
    } on Object catch (e) {
      yield StreamSendFailed(_message(e));
    } finally {
      await conn?.close();
    }
  }

  // ---- Receiver ----

  /// Join a session by code and receive the streamed file to disk (recorded in
  /// the Inbox). Signature matches [CloudTransferService] so it reuses the same
  /// glass download modal.
  Future<ReceivedFile> receive(
    String code, {
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final channel = WebSocketChannel.connect(_wsUri);
    _Conn? conn;
    IOSink? sink;
    File? target;
    try {
      await channel.ready;
      conn = _Conn(channel)..start();

      conn.sendText({
        'type': 'join',
        'data': {'code': code.replaceAll('-', '').toUpperCase()},
      });
      final info = await conn.waitText('file-info', const Duration(seconds: 15));
      final fileName = (info['fileName'] as String?) ?? 'file';
      final total = (info['totalSize'] as num?)?.toInt() ?? 0;
      final senderAlias = (info['senderAlias'] as String?) ?? 'Nearby device';
      conn.sendText({'type': 'accept'});

      target = await _uniquePath(fileName);
      sink = target.openWrite();
      final decoder = FrameDecoder();
      String expectedSha = '';
      String mime = '';
      var received = 0;
      var done = false;

      Digest? finalDigest;
      final hashInput = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((d) => finalDigest = d.single),
      );

      // Fail cleanly if the stream stalls (peer vanished) rather than hang.
      final stream = conn.binary.timeout(
        const Duration(seconds: 45),
        onTimeout: (sink) => sink.addError(
          const CloudDownloadException('The transfer stalled — please retry.'),
        ),
      );
      await for (final data in stream) {
        if (cancel != null && cancel.isCancelled) {
          throw cancel.cancelError ??
              DioException(requestOptions: RequestOptions(), type: DioExceptionType.cancel);
        }
        for (final frame in decoder.add(data)) {
          switch (frame.type) {
            case FrameType.fileStart:
              final meta =
                  jsonDecode(utf8.decode(frame.payload)) as Map<String, dynamic>;
              expectedSha = (meta['sha256'] as String?) ?? '';
              mime = (meta['fileType'] as String?) ?? '';
            case FrameType.fileData:
              sink.add(frame.payload);
              hashInput.add(frame.payload);
              received += frame.payload.length;
              onProgress?.call(received, total);
            case FrameType.sessionEnd:
              done = true;
          }
        }
        if (done) break;
      }

      await sink.flush();
      await sink.close();
      sink = null;
      hashInput.close();

      if (expectedSha.isNotEmpty &&
          finalDigest != null &&
          finalDigest.toString() != expectedSha) {
        await target.delete().catchError((_) => target!);
        throw const CloudDownloadException('Transfer verification failed');
      }

      final saved = ReceivedFile(
        fileName: target.uri.pathSegments.last,
        savedPath: target.path,
        size: await target.length(),
        senderAlias: senderAlias,
        receivedAt: DateTime.now(),
        verified: expectedSha.isNotEmpty,
        fileType: mime.isEmpty ? null : mime,
      );
      await _history.recordReceived(saved);
      return saved;
    } finally {
      await sink?.close();
      await conn?.close();
    }
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

  static String _message(Object e) {
    if (e is CloudDownloadException) return e.message;
    if (e is TimeoutException) return 'The other device didn\'t respond in time';
    return 'The connection failed. Please try again.';
  }
}

/// Wraps a stream-relay WebSocket: routes text control frames to typed waiters
/// (with a small buffer for races) and exposes binary frames as a stream.
class _Conn {
  _Conn(this._channel);
  final WebSocketChannel _channel;

  final Map<String, Completer<Map<String, dynamic>>> _waiters = {};
  final Map<String, Map<String, dynamic>> _pending = {};
  final StreamController<Uint8List> _binary = StreamController<Uint8List>();
  Object? _fatal;

  Stream<Uint8List> get binary => _binary.stream;

  void start() {
    _channel.stream.listen(
      (msg) {
        if (msg is String) {
          _onText(msg);
        } else if (msg is List<int>) {
          _binary.add(Uint8List.fromList(msg));
        }
      },
      onDone: () {
        if (!_binary.isClosed) _binary.close();
      },
      onError: (Object _) {
        if (!_binary.isClosed) _binary.close();
      },
    );
  }

  void _onText(String raw) {
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on Object {
      return;
    }
    final type = m['type'] as String?;
    if (type == null) return;
    final data = m['data'] is Map
        ? (m['data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    if (type == 'error' || type == 'rejected' || type == 'peer-left') {
      _fatal = CloudDownloadException(
        type == 'rejected'
            ? 'The transfer was declined'
            : type == 'peer-left'
            ? 'The other device disconnected'
            : (data['message'] as String?) ?? 'Stream error',
      );
      // Fail any outstanding text waiter immediately.
      for (final c in _waiters.values) {
        if (!c.isCompleted) c.completeError(_fatal!);
      }
      _waiters.clear();
      // Surface into the binary path too (the receiver's `await for` loop has
      // no text waiter mid-transfer, so it would otherwise hang forever).
      if (!_binary.isClosed) {
        _binary.addError(_fatal!);
        _binary.close();
      }
      return;
    }
    final waiter = _waiters.remove(type);
    if (waiter != null) {
      waiter.complete(data);
    } else {
      _pending[type] = data;
    }
  }

  Future<Map<String, dynamic>> waitText(String type, Duration timeout) {
    if (_fatal != null) return Future.error(_fatal!);
    final buffered = _pending.remove(type);
    if (buffered != null) return Future.value(buffered);
    final c = Completer<Map<String, dynamic>>();
    _waiters[type] = c;
    return c.future.timeout(timeout);
  }

  void sendText(Map<String, dynamic> m) => _channel.sink.add(jsonEncode(m));
  void sendBinary(Uint8List bytes) => _channel.sink.add(bytes);

  Future<void> close() async {
    try {
      await _channel.sink.close();
    } on Object {
      // already closed
    }
    if (!_binary.isClosed) await _binary.close();
  }
}
