import 'dart:async';
import 'dart:typed_data';


import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../src/rust/api/quic.dart' as quic;
import '../../settings/domain/settings.dart' show TransportMode;

import '../../../core/constants/protocol.dart';
import '../../../core/error/exceptions.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/protocol/device_info.dart';
import '../../../core/protocol/file_metadata.dart';
import '../../../core/protocol/file_request.dart';
import '../../../core/protocol/goodbye_request.dart';
import '../../../core/protocol/prepare.dart';
import '../../../core/rust/rust_facade.dart';
import '../../discovery/domain/discovered_device.dart';
import '../domain/sendable_file.dart';
import 'send_api_service.dart';

/// Progress callback: overall + per-file byte counters.
typedef SendProgress =
    void Function(
      int fileIndex,
      int fileCount,
      String fileName,
      int overallSent,
      int overallTotal,
    );

/// The LAN sender. Idempotent JSON endpoints (info/cancel/goodbye) go through
/// Retrofit ([SendApiService]) with automatic retry; the streamed upload uses raw
/// Dio with a manual, fresh-nonce retry. When the receiver advertises a `publicKey`
/// the upload is E2E-encrypted+framed (byte-exact with native) via Rust FFI.
class TransferClient {
  TransferClient(this._identity);

  final DeviceIdentity _identity;
  final _uuid = const Uuid();

  /// Transport preference from Settings. Set by [SettingsCubit].
  TransportMode preferredTransport = TransportMode.auto;

  /// Whether to send this file over QUIC. The transport is **symmetric** — the
  /// sender's choice drives the receiver, which runs both a TCP and a QUIC server
  /// and simply accepts whichever stream arrives:
  ///   • **TCP**  → always TCP (kernel; fastest on a clean LAN).
  ///   • **QUIC** → always QUIC (userspace quinn; wins on WAN/lossy links, but on
  ///     a LAN — especially Apple, which lacks UDP GSO — it is slower than TCP).
  ///   • **Auto** → TCP on the LAN (fast, universal default); reserved to pick
  ///     QUIC automatically for the future remote/relay path.
  /// A QUIC attempt also requires the target to advertise a quicPort (see [send]);
  /// otherwise it falls back to TCP.
  bool _shouldUseQuic() => switch (preferredTransport) {
    TransportMode.tcp => false,
    TransportMode.quic => true,
    TransportMode.auto => false,
  };

  Dio _dioFor(String host, int port) => Dio(
    BaseOptions(
      baseUrl: 'http://$host:$port',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 30),
      responseType: ResponseType.json,
      // Inspect status codes ourselves (401/403/409 are meaningful).
      validateStatus: (_) => true,
    ),
  );

  /// Retrofit client for the idempotent JSON endpoints, with automatic
  /// retry/backoff (safe — GET info / cancel / goodbye are idempotent; the
  /// non-idempotent upload retries manually with a fresh nonce instead).
  SendApiService _apiService(String host, int port) {
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://$host:$port',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        responseType: ResponseType.json,
      ),
    );
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        retries: 2,
        retryDelays: const [
          Duration(milliseconds: 200),
          Duration(milliseconds: 500),
        ],
      ),
    );
    return SendApiService(dio);
  }

  /// Probe a peer's `/api/v1/info` (retried on transient failure).
  Future<DeviceInfo> fetchInfo(String host, int port) async {
    try {
      return await _apiService(host, port).getInfo();
    } on DioException catch (e) {
      throw TransferHttpException(e.response?.statusCode ?? 0, e.message);
    }
  }

  /// Reverse flow: ask [device] to send US files. The receiver holds the
  /// connection while its user decides (auto-declines after 60s), so this uses a
  /// long receive timeout. Returns whether the request was accepted.
  Future<FileRequestResponse> sendFileRequest(
    DiscoveredDevice device,
    String? message,
  ) async {
    final info = await _identity.makeDeviceInfo();
    final req = FileRequestMessage(
      requestId: _uuid.v4(),
      requesterAlias: info.alias,
      requesterFingerprint: info.fingerprint,
      requesterHost: info.ip ?? '',
      requesterPort: BISharePort.main,
      message: (message != null && message.isNotEmpty) ? message : null,
    );
    final dio = Dio(
      BaseOptions(
        baseUrl: 'http://${device.host}:${device.port}',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 70), // peer holds up to 60s
        sendTimeout: const Duration(seconds: 10),
        validateStatus: (_) => true,
      ),
    );
    try {
      final res = await dio.post<Map<String, dynamic>>(
        BIShareApi.request,
        data: req.toJson(),
      );
      if (res.statusCode != BIShareStatus.ok || res.data == null) {
        throw TransferHttpException(res.statusCode ?? 0);
      }
      return FileRequestResponse.fromJson(res.data!);
    } on DioException catch (e) {
      throw TransferHttpException(e.response?.statusCode ?? 0, e.message);
    }
  }

  /// Sends [files] to [device]. Emits progress and throws a [TransferHttpException]
  /// / [CancelledException] on failure.
  Future<void> send(
    List<SendableFile> files,
    DiscoveredDevice device, {
    String? pin,
    SendProgress? onProgress,
    CancelToken? cancelToken,
    void Function(String sessionId)? onSession,
    void Function(String transport)? onTransport,
  }) async {
    final dio = _dioFor(device.host, device.port);
    final info = await _identity.makeDeviceInfo();

    // Build file metadata (streaming SHA-256, no whole-file buffering).
    final metas = <String, FileMetadata>{};
    for (final f in files) {
      metas[f.id] = FileMetadata(
        id: f.id,
        fileName: f.name,
        size: f.size,
        fileType: f.mimeType,
        // Large files skip the upfront full-file hash so "Preparing" stays
        // instant and the file is read once (not twice). Encrypted transfers
        // keep integrity via per-chunk AES-GCM auth; small files still verify.
        sha256: f.size <= _hashSizeLimit ? await _sha256(f) : null,
      );
    }

    // Step 1: prepare.
    final prepareRes = await dio.post<Map<String, dynamic>>(
      BIShareApi.prepare,
      queryParameters: pin != null ? {'pin': pin} : null,
      data: PrepareRequest(info: info, files: metas).toJson(),
      cancelToken: cancelToken,
    );
    switch (prepareRes.statusCode) {
      case BIShareStatus.ok:
        break;
      case BIShareStatus.pinRequired:
        throw const TransferHttpException(BIShareStatus.pinRequired);
      case BIShareStatus.forbidden:
        // 403 covers BOTH "Wrong PIN" and "Transfer rejected" — carry the
        // server's message so the sender can tell them apart.
        throw TransferHttpException(
          BIShareStatus.forbidden,
          prepareRes.data?['message'] as String?,
        );
      case BIShareStatus.busy:
        throw const TransferHttpException(BIShareStatus.busy);
      default:
        throw TransferHttpException(prepareRes.statusCode ?? 0);
    }
    final prepare = PrepareResponse.fromJson(prepareRes.data!);
    onSession?.call(prepare.sessionId);
    // Cancelling the transfer also aborts any in-flight QUIC send (the Rust send
    // loop polls this cancel id and resets the stream so the receiver discards it).
    cancelToken?.whenCancel.then(
      (_) => quic.quicCancel(cancelId: prepare.sessionId),
    );

    // E2E: if the receiver advertised a public key, derive the shared key and
    // encrypt the upload (symmetric with the receiver's own derivation).
    final receiverPub = prepare.publicKey;
    final key = (receiverPub != null && receiverPub.isNotEmpty)
        ? _identity.deriveKey(receiverPub)
        : null;

    // Step 2: upload each file (sequential in P0; bounded parallelism is P1).
    final totalBytes = files.fold<int>(0, (s, f) => s + f.size);
    var overallSent = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final token = prepare.files[f.id];
      if (token == null) {
        throw TransferHttpException(
          BIShareStatus.serverError,
          'no token for ${f.name}',
        );
      }
      final base = overallSent;

      // Prefer QUIC when the peer advertises it and the setting allows it (TLS 1.3
      // transport encryption, no app-layer E2E — mirrors native). Fall back to the
      // HTTP/TCP path on any QUIC failure so a transfer never dead-ends.
      if (_shouldUseQuic() && f.size > 0 && device.quicPort != null) {
        onTransport?.call('QUIC'); // reflect the transport DURING the transfer
        try {
          await _uploadViaQuic(
            f,
            device,
            prepare.sessionId,
            info,
            onProgress: onProgress,
            index: i,
            count: files.length,
            base: base,
            total: totalBytes,
          );
          overallSent += f.size;
          onProgress?.call(i, files.length, f.name, overallSent, totalBytes);
          continue;
        } on Object catch (e) {
          debugPrint('[Client] QUIC upload failed ($e) — falling back to TCP');
        }
      }
      onTransport?.call('TCP');

      // Upload with bounded retry/backoff. A retry re-uploads the whole file (no
      // Range resume — the receiver Range gap is deferred), and each attempt calls
      // _encryptedBody fresh so it gets a NEW baseNonce — reusing a nonce across
      // attempts would be catastrophic for AES-GCM. 5xx / transport errors are
      // retryable; 4xx (bad token, rejected) is terminal and fails immediately.
      for (var attempt = 1; ; attempt++) {
        final Stream<List<int>> body;
        final headers = <String, dynamic>{};
        if (key != null) {
          final chunkCount = f.size == 0
              ? 0
              : (f.size + _chunkSize - 1) ~/ _chunkSize;
          headers[Headers.contentLengthHeader] =
              f.size + chunkCount * (4 + BIShareCrypto.gcmOverheadPerChunk);
          headers['X-Encrypted'] = 'chunked';
          body = _encryptedBody(f, key); // fresh baseNonce per attempt
        } else {
          headers[Headers.contentLengthHeader] = f.size;
          body = f.file.openRead();
        }

        try {
          final res = await dio.post<Map<String, dynamic>>(
            BIShareApi.upload,
            queryParameters: {
              'sessionId': prepare.sessionId,
              'fileId': f.id,
              'token': token,
            },
            data: body,
            options: Options(
              headers: headers,
              contentType: 'application/octet-stream',
            ),
            cancelToken: cancelToken,
            // `sent` counts wire bytes (encrypted ≈ plaintext); clamp per file so
            // overall progress stays monotonic against the plaintext total.
            onSendProgress: (sent, _) => onProgress?.call(
              i,
              files.length,
              f.name,
              base + (sent > f.size ? f.size : sent),
              totalBytes,
            ),
          );
          final status = res.statusCode ?? 0;
          if (status >= 500 && attempt < _maxUploadAttempts) {
            await _backoff(attempt);
            continue; // retryable server error
          }
          if (status != BIShareStatus.ok) {
            throw TransferHttpException(status); // terminal
          }
          break; // uploaded
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) rethrow;
          if (attempt < _maxUploadAttempts) {
            await _backoff(attempt); // transport error — retryable
            continue;
          }
          throw TransferHttpException(0, e.message);
        }
      }
      overallSent += f.size;
      onProgress?.call(i, files.length, f.name, overallSent, totalBytes);
    }
  }

  static const int _maxUploadAttempts = 3;

  /// Files at or below this size are hashed upfront (SHA-256 in prepare, cheap +
  /// verified); larger files skip it to keep "Preparing" instant.
  static const int _hashSizeLimit = 64 * 1024 * 1024; // 64 MB

  Future<void> _backoff(int attempt) =>
      Future<void>.delayed(Duration(milliseconds: 300 * attempt));

  /// Upload one file over QUIC, forwarding the Rust send stream's byte progress.
  /// Throws on any failure so [send] can fall back to the HTTP/TCP path.
  Future<void> _uploadViaQuic(
    SendableFile f,
    DiscoveredDevice device,
    String sessionId,
    DeviceInfo info, {
    SendProgress? onProgress,
    required int index,
    required int count,
    required int base,
    required int total,
  }) async {
    final stream = quic.quicSendFile(
      host: device.host,
      port: device.quicPort!,
      cancelId: sessionId, // one cancel token per transfer
      sessionId: sessionId,
      fileId: f.id,
      senderAlias: info.alias,
      senderFingerprint: info.fingerprint,
      filePath: f.path,
      fileName: f.name,
      fileType: f.mimeType,
    );
    await for (final sent in stream) {
      onProgress?.call(index, count, f.name, base + sent.toInt(), total);
    }
  }

  static const int _chunkSize = BIShareConfig.defaultChunkSize;

  /// Streams a file as E2E frames: `[uint32 BE length][ nonce|ciphertext|tag ]`,
  /// re-chunked to exactly [_chunkSize] plaintext bytes (last chunk may be smaller).
  /// Encryption runs in shared Rust (`encrypt_chunk`) for byte-exact interop.
  ///
  /// Uses [BytesBuilder] + `Uint8List` views throughout — never a boxed `List<int>`
  /// — so re-chunking is zero-copy and FFI marshalling is a fast memcpy (the boxed
  /// path measured ~2 MB/s; this clears the 40 MB/s gate).
  Stream<List<int>> _encryptedBody(SendableFile f, List<int> key) async* {
    final baseNonce = Rust.generateBaseNonce();
    var index = 0;
    final acc = BytesBuilder(copy: false);
    // `await Rust.encryptChunk` runs AES on FRB's Rust worker pool, so the event
    // loop is free *during the await* — dio drains the previously-yielded frame
    // to the socket while chunk N encrypts. That depth-1 network↔crypto overlap
    // is the fix for the ~17 MB/s wall (crypto was `frb(sync)` = main-isolate).
    await for (final data in f.file.openRead()) {
      acc.add(data);
      while (acc.length >= _chunkSize) {
        final buf = acc.takeBytes(); // Uint8List; drains the builder
        final plain = Uint8List.sublistView(buf, 0, _chunkSize);
        yield _frame((await Rust.encryptChunk(plain, key, index, baseNonce))!);
        index++;
        if (buf.length > _chunkSize) {
          acc.add(Uint8List.sublistView(buf, _chunkSize));
        }
      }
    }
    if (acc.length > 0) {
      yield _frame((await Rust.encryptChunk(acc.toBytes(), key, index, baseNonce))!);
    }
  }

  Uint8List _frame(List<int> enc) {
    final len = enc.length;
    final out = Uint8List(4 + len)
      ..[0] = (len >> 24) & 0xFF
      ..[1] = (len >> 16) & 0xFF
      ..[2] = (len >> 8) & 0xFF
      ..[3] = len & 0xFF;
    out.setRange(4, 4 + len, enc);
    return out;
  }

  /// Tell the receiver to abort [sessionId] (called when the sender cancels).
  Future<void> cancel(String sessionId, DiscoveredDevice device) async {
    try {
      await _apiService(device.host, device.port).cancel(sessionId);
    } on DioException {
      // best-effort — the receiver also idle-expires the session
    }
  }

  /// Notify a peer we are going offline.
  Future<void> sendGoodbye(DiscoveredDevice device) async {
    try {
      await _apiService(
        device.host,
        device.port,
      ).goodbye(GoodbyeRequest(fingerprint: _identity.fingerprint));
    } on DioException {
      // best-effort
    }
  }

  Future<String> _sha256(SendableFile f) async {
    final digest = await sha256.bind(f.file.openRead()).first;
    return digest.toString();
  }
}
