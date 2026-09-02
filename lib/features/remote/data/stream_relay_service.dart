import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/crypto/bse2.dart';
import '../../../core/io/scratch_dir.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../history/data/history_repository.dart';
import 'binary_frame.dart';
import 'cloud_transfer_service.dart' show ProgressCb, CloudDownloadException;

/// Events surfaced while sending over the stream relay (drives the sender UI).
sealed class StreamSendEvent {
  const StreamSendEvent();
}

/// The session code is ready — present `bishare-stream://<code>[#k=<key>]`
/// as a QR. [key] is the end-to-end key when the file was sealed: it belongs
/// in the QR fragment only, never in the displayed code, never on the relay.
class StreamCodeReady extends StreamSendEvent {
  const StreamCodeReady(this.code, {this.key});
  final String code;
  final String? key;
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
///
/// Two things ride on top of the raw frames, both invisible to the relay:
///
/// * **End-to-end encryption.** The sender seals the file into a BSE2
///   container (shared Rust code, see [Bse2]) and streams the ciphertext; the
///   key travels only in the QR fragment. The relay forwards bytes it cannot
///   read — which is the only way "nothing is stored" also means "nothing is
///   readable".
/// * **Flow control.** The relay forwards with no backpressure of its own, so
///   a receiver slower than the sender would make it buffer the difference in
///   memory. The receiver acknowledges bytes as they land and the sender never
///   lets more than [ackWindow] go unacknowledged.
///
/// Both are announced by the receiver in a `hello` frame right after `accept`.
/// A receiver that sends no `hello` is a previous app version: it can neither
/// decrypt nor acknowledge, so an encrypted send stops there with a clear
/// message instead of handing it bytes it would save as garbage.
class StreamRelayService {
  StreamRelayService(this._server, this._history, {Uri? wsUri})
    : _wsUri = wsUri ?? Uri.parse('${CloudConfig.wsBase}${CloudConfig.stream}');

  final TransferServer _server;
  final HistoryRepository _history;
  final Uri _wsUri;

  /// Bytes the sender may have in flight beyond the receiver's last
  /// acknowledgement. Big enough to keep a fast link busy, small enough that
  /// the relay never holds more than this per session.
  static const int ackWindow = 8 * 1024 * 1024;

  /// The receiver acknowledges at least this often (and always at the end).
  static const int ackEvery = 1024 * 1024;

  /// How long the sender waits for the receiver to catch up before giving up.
  static const Duration ackStallTimeout = Duration(seconds: 45);

  // ---- Sender ----

  /// Stream a file to whoever scans the returned code. Emits [StreamCodeReady]
  /// (present the QR), then [StreamReceiverJoined], progress, and completion.
  Stream<StreamSendEvent> send(
    File file, {
    required String fileName,
    required String mimeType,
    required String senderAlias,
    bool encrypt = true,
  }) async* {
    final plainSize = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    final sha = digest.toString();

    Directory? scratch;
    var body = file;
    String? keyFragment;
    final channel = WebSocketChannel.connect(_wsUri);
    _Conn? conn;
    try {
      if (encrypt) {
        final raw = Bse2.generateKey();
        keyFragment = Bse2.encodeKey(raw);
        scratch = await createScratchDir('bishare-live-');
        body = File('${scratch.path}${Platform.pathSeparator}live.bse2');
        await Bse2.encryptFile(input: file, output: body, key: raw);
      }
      // What crosses the wire — the container when sealed, the file otherwise.
      final size = await body.length();

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
      final created = await conn.waitText(
        'created',
        const Duration(seconds: 15),
      );
      yield StreamCodeReady(
        (created['code'] as String?) ?? '',
        key: keyFragment,
      );

      await conn.waitText('joined', const Duration(minutes: 10));
      await conn.waitText('accepted', const Duration(seconds: 30));

      // A current receiver announces itself right behind `accept`; a legacy
      // one never will, so a short wait is all it costs to find out.
      Map<String, dynamic>? hello;
      try {
        hello = await conn.waitText(
          'hello',
          const Duration(milliseconds: 1500),
        );
      } on TimeoutException {
        hello = null;
      }
      final peerDecrypts = hello?['e2e'] == true;
      final peerAcks = hello?['ack'] == true;
      if (encrypt && !peerDecrypts) {
        throw CloudDownloadException('remote.live_receiver_needs_update'.tr());
      }
      yield const StreamReceiverJoined();

      conn.sendBinary(
        encodeJsonFrame(FrameType.fileStart, 0, {
          'fileName': fileName,
          'size': size,
          'plainSize': plainSize,
          'fileType': mimeType,
          'sha256': sha,
          'encrypted': encrypt,
        }),
      );

      var sent = 0;
      await for (final chunk in body.openRead()) {
        if (peerAcks && sent + chunk.length - conn.acked > ackWindow) {
          // The receiver is behind; wait for it rather than let the relay
          // buffer the difference.
          await conn.waitAcked(
            sent + chunk.length - ackWindow,
            ackStallTimeout,
          );
        }
        conn.sendBinary(encodeFrame(FrameType.fileData, 0, chunk));
        sent += chunk.length;
        yield StreamSendProgress(size == 0 ? 1 : sent / size);
      }

      conn.sendBinary(
        encodeJsonFrame(FrameType.fileEnd, 0, {
          'verified': true,
          'encrypted': encrypt,
        }),
      );
      conn.sendBinary(encodeFrame(FrameType.sessionEnd, 0, const []));
      if (peerAcks) {
        // Completion means the receiver has processed session end, not that
        // the relay has accepted our last frame.
        await conn.waitDone(ackStallTimeout);
      } else {
        // Give the relay a moment to flush the tail before we tear down.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      yield const StreamSendComplete();
    } on Object catch (e) {
      yield StreamSendFailed(_message(e));
    } finally {
      await conn?.close();
      if (scratch != null) {
        try {
          await scratch.delete(recursive: true);
        } on Object {
          // Best effort: the OS reclaims its temp dir anyway.
        }
      }
    }
  }

  // ---- Receiver ----

  /// Join a session by code and receive the streamed file to disk (recorded in
  /// the Inbox). Signature matches [CloudTransferService] so it reuses the same
  /// glass download modal.
  /// [key] is the QR fragment's end-to-end key; without it a sealed session
  /// is refused honestly rather than saved as unreadable bytes.
  Future<ReceivedFile> receive(
    String code, {
    String? key,
    ProgressCb? onProgress,
    CancelToken? cancel,
  }) async {
    final channel = WebSocketChannel.connect(_wsUri);
    _Conn? conn;
    IOSink? sink;
    File? target;
    File? sealed;
    try {
      await channel.ready;
      conn = _Conn(channel)..start();

      conn.sendText({
        'type': 'join',
        'data': {'code': code.replaceAll('-', '').toUpperCase()},
      });
      final info = await conn.waitText(
        'file-info',
        const Duration(seconds: 15),
      );
      final fileName = (info['fileName'] as String?) ?? 'file';
      final total = (info['totalSize'] as num?)?.toInt() ?? 0;
      final senderAlias = (info['senderAlias'] as String?) ?? 'Nearby device';
      conn.sendText({'type': 'accept'});
      // Announce what this receiver can do. The relay forwards it untouched;
      // a legacy sender simply ignores it.
      conn.sendText({
        'type': 'hello',
        'data': {'e2e': true, 'ack': true},
      });
      // Signal that a session was actually joined (file-info received) before any
      // bytes flow — lets callers tell a real-but-failed session apart from a
      // code that nothing answered.
      onProgress?.call(0, total);

      target = await _uniquePath(fileName);
      sink = target.openWrite();
      final decoder = FrameDecoder();
      String expectedSha = '';
      String mime = '';
      var encrypted = false;
      Uint8List? rawKey;
      var received = 0;
      var unacked = 0;
      var done = false;

      void ack({bool done = false}) {
        conn!.sendText({
          'type': 'ack',
          'data': {'received': received, if (done) 'done': true},
        });
        unacked = 0;
      }

      Digest? finalDigest;
      final hashInput = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback(
          (d) => finalDigest = d.single,
        ),
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
              DioException(
                requestOptions: RequestOptions(),
                type: DioExceptionType.cancel,
              );
        }
        for (final frame in decoder.add(data)) {
          switch (frame.type) {
            case FrameType.fileStart:
              final meta =
                  jsonDecode(utf8.decode(frame.payload))
                      as Map<String, dynamic>;
              expectedSha = (meta['sha256'] as String?) ?? '';
              mime = (meta['fileType'] as String?) ?? '';
              encrypted = meta['encrypted'] == true;
              if (encrypted) {
                rawKey = key == null ? null : Bse2.decodeKey(key);
                if (rawKey == null) {
                  throw CloudDownloadException(
                    'remote.encrypted_needs_link'.tr(),
                  );
                }
                // Ciphertext lands beside the target and is opened into it
                // once every record has authenticated.
                await sink!.close();
                sealed = File('${target.path}.bse2');
                sink = sealed.openWrite();
              }
            case FrameType.fileData:
              sink!.add(frame.payload);
              if (!encrypted) hashInput.add(frame.payload);
              received += frame.payload.length;
              unacked += frame.payload.length;
              if (unacked >= ackEvery) ack();
              onProgress?.call(received, total);
            case FrameType.sessionEnd:
              done = true;
          }
        }
        if (done) break;
      }

      await sink!.flush();
      await sink.close();
      sink = null;
      hashInput.close();
      // The final acknowledgement — marked done — is what lets the sender
      // report completion and hang up. A byte count alone is not enough: when
      // the size is a whole number of ack intervals, the last byte ack goes
      // out before the session-end frame has arrived, and a sender that hung
      // up on it would leave this side reading a dead socket.
      ack(done: true);

      var verified = expectedSha.isNotEmpty;
      if (encrypted) {
        // Every record carries its own authentication tag, so a successful
        // open IS the integrity check; no second pass over the plaintext.
        try {
          await Bse2.decryptFile(input: sealed!, output: target, key: rawKey!);
        } on Bse2Exception {
          await target.delete().catchError((_) => target!);
          throw CloudDownloadException('remote.encrypted_bad_key'.tr());
        } finally {
          await sealed!.delete().catchError((_) => sealed!);
        }
        verified = true;
      } else if (expectedSha.isNotEmpty &&
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
        verified: verified,
        fileType: mime.isEmpty ? null : mime,
      );
      await _history.recordReceived(saved);
      return saved;
    } catch (_) {
      // Never leave the reserved (or half-written) target behind on failure.
      if (target != null && await target.exists()) {
        await target.delete().catchError((_) => target!);
      }
      rethrow;
    } finally {
      await sink?.close();
      await conn?.close();
      if (sealed != null && await sealed.exists()) {
        await sealed.delete().catchError((_) => sealed!);
      }
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
    if (e is TimeoutException) {
      return 'The other device didn\'t respond in time';
    }
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

  /// Highest byte count the peer has acknowledged (`ack` frames).
  int acked = 0;

  /// The peer's final ack, sent once it has processed session end.
  bool done = false;
  Completer<void>? _ackWaiter;

  /// Resolves once the peer reports it has processed session end.
  Future<void> waitDone(Duration timeout) async {
    while (!done) {
      if (_fatal != null) throw _fatal!;
      final c = _ackWaiter = Completer<void>();
      try {
        await c.future.timeout(timeout);
      } on TimeoutException {
        throw const CloudDownloadException(
          'The transfer stalled — please retry.',
        );
      }
    }
  }

  /// Resolves once the peer has acknowledged at least [atLeast] bytes; fails
  /// after [timeout] without progress, or at once if the session is dead.
  Future<void> waitAcked(int atLeast, Duration timeout) async {
    while (acked < atLeast) {
      if (_fatal != null) throw _fatal!;
      final c = _ackWaiter = Completer<void>();
      try {
        await c.future.timeout(timeout);
      } on TimeoutException {
        throw const CloudDownloadException(
          'The transfer stalled — please retry.',
        );
      }
    }
  }

  void _wakeAck() {
    final w = _ackWaiter;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// Once the consumer is done (loop exited, [close] called) the socket may
  /// still deliver a tail — the peer's final frames, its `peer-left` — and
  /// a single-subscription controller with no listener would turn those into
  /// unhandled errors. Everything after that point is dropped on purpose.
  bool _done = false;

  void start() {
    _channel.stream.listen(
      (msg) {
        if (_done) return;
        if (msg is String) {
          _onText(msg);
        } else if (msg is List<int>) {
          if (_binary.hasListener) _binary.add(Uint8List.fromList(msg));
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
      _wakeAck(); // waitAcked re-checks _fatal and throws
      // Surface into the binary path too (the receiver's `await for` loop has
      // no text waiter mid-transfer, so it would otherwise hang forever).
      if (!_binary.isClosed) {
        if (_binary.hasListener) _binary.addError(_fatal!);
        _binary.close();
      }
      return;
    }
    if (type == 'ack') {
      final n = (data['received'] as num?)?.toInt() ?? 0;
      if (n > acked) acked = n;
      if (data['done'] == true) done = true;
      _wakeAck();
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
    _done = true;
    try {
      await _channel.sink.close();
    } on Object {
      // already closed
    }
    if (!_binary.isClosed) await _binary.close();
  }
}
