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

    // Step 1: prepare. A fresh install's FIRST outbound LAN connection can be
    // silently dropped by iOS/macOS until the Local Network permission grant
    // lands, so a single connect failure must not doom the whole send — retry
    // the CONNECT a few times with backoff. Only connection-establishment
    // failures are retried: a slow *accept* surfaces as a receiveTimeout (the
    // receiver holds the response up to `acceptRejectTimeout`), and retrying
    // that would re-prompt the receiver. The response window is also widened
    // past the receiver's 30 s accept timeout so a last-second accept never
    // loses a dead-heat race with the sender's timeout.
    late final Response<Map<String, dynamic>> prepareRes;
    for (var attempt = 1; ; attempt++) {
      try {
        prepareRes = await dio.post<Map<String, dynamic>>(
          BIShareApi.prepare,
          queryParameters: pin != null ? {'pin': pin} : null,
          data: PrepareRequest(info: info, files: metas).toJson(),
          cancelToken: cancelToken,
          options: Options(
            receiveTimeout:
                BIShareConfig.acceptRejectTimeout + const Duration(seconds: 15),
          ),
        );
        break;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        final isConnectFailure =
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.connectionError;
        if (isConnectFailure && attempt < _maxPrepareAttempts) {
          await _backoff(attempt);
          continue; // first-connection stall (e.g. LAN permission) — retry
        }
        throw TransferHttpException(0, e.message);
      }
    }
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

    // Step 2: upload. Phase 2b: QUIC-eligible files run CONCURRENTLY over the
    // single reused connection, bounded by the receiver-advertised maxConcurrent
    // (finally honoring the negotiation instead of ignoring it); failures and
    // QUIC-ineligible files then run sequentially over TCP.
    final totalBytes = files.fold<int>(0, (s, f) => s + f.size);
    // Per-file byte counters — with concurrent sends the overall progress is the
    // SUM across files, not a running scalar.
    final sentPerFile = List<int>.filled(files.length, 0);
    void emitOverall(int i) {
      var sum = 0;
      for (final s in sentPerFile) {
        sum += s;
      }
      onProgress?.call(
        i,
        files.length,
        files[i].name,
        sum > totalBytes ? totalBytes : sum,
        totalBytes,
      );
    }

    // Every file needs a token — fail before any bytes move.
    for (final f in files) {
      if (prepare.files[f.id] == null) {
        throw TransferHttpException(
          BIShareStatus.serverError,
          'no token for ${f.name}',
        );
      }
    }

    // Phase 1a: open ONE persistent QUIC connection for the whole session (a
    // single handshake reused for every file) instead of a handshake per file.
    // On any failure we fall back to the HTTP/TCP path for all files.
    var quicReady = false;
    if (_shouldUseQuic() && device.quicPort != null) {
      try {
        await quic.quicConnect(
          host: device.host,
          port: device.quicPort!,
          sessionId: prepare.sessionId,
        );
        quicReady = true;
        debugPrint(
          '[Client] QUIC connected ${device.host}:${device.quicPort} — '
          'ONE handshake reused for ${files.length} file(s)',
        );
      } on Object catch (e) {
        debugPrint(
          '[Client] QUIC connect failed ($e) — using TCP this session',
        );
      }
    }

    try {
      // ── Phase A: concurrent QUIC ────────────────────────────────────────────
      // Files that fail QUIC (or can't use it) land in tcpQueue for Phase B.
      final tcpQueue = <int>[];
      if (quicReady) {
        final quicIdx = <int>[];
        for (var i = 0; i < files.length; i++) {
          (files[i].size > 0 ? quicIdx : tcpQueue).add(i);
        }
        // Clamp to the Rust-side MAX_STREAMS (8) so the envelope math below is
        // computed with the value that will actually be used.
        final streams = (prepare.streamsPerFile ?? 1).clamp(1, 8);
        final chunkSize = prepare.chunkSize ?? BIShareConfig.defaultChunkSize;
        // Receiver-authoritative concurrency, ENFORCED against the slab-pool
        // envelope: files × streams must stay ≤ 16 slabs per direction, whatever
        // a peer advertises (a peer pushing streamsPerFile=8 gets 2 concurrent
        // files, not 4 × 8 = 32 slab waiters and spurious pool timeouts).
        final envelopeCap = streams > 0 ? (16 ~/ streams).clamp(1, 8) : 1;
        final concurrency = (prepare.maxConcurrent ?? 1).clamp(
          1,
          _maxConcurrentQuicFiles < envelopeCap
              ? _maxConcurrentQuicFiles
              : envelopeCap,
        );
        if (quicIdx.isNotEmpty) {
          onTransport?.call('QUIC');
          debugPrint(
            '[Client] QUIC phase: ${quicIdx.length} file(s), '
            'concurrency $concurrency',
          );
        }
        // Single-threaded event loop: the next/++ below is race-free.
        var next = 0;
        Future<void> worker() async {
          while (next < quicIdx.length) {
            // A user cancel must stop workers from STARTING new files too — the
            // Rust poison only fails sends already in flight.
            final ct = cancelToken;
            if (ct != null && ct.isCancelled) {
              throw ct.cancelError ??
                  DioException.requestCancelled(
                    requestOptions: RequestOptions(),
                    reason: 'cancelled',
                  );
            }
            final i = quicIdx[next++];
            final f = files[i];
            try {
              await _uploadViaQuic(
                f,
                prepare.sessionId,
                info,
                // Receiver-authoritative multi-stream geometry (Phase 1b).
                streams: streams,
                chunkSize: chunkSize,
                // Phase 4: resume if the receiver keeps a ledger — a reconnect
                // after a drop then skips already-received chunks.
                resume: prepare.supportsResume ?? false,
                onBytes: (sent) {
                  sentPerFile[i] = sent > f.size ? f.size : sent;
                  emitOverall(i);
                },
              );
              sentPerFile[i] = f.size;
              emitOverall(i);
            } on Object catch (e) {
              // A USER cancel surfaces here too (the Rust send errors
              // "cancelled") — abort everything, don't re-send over TCP.
              final ct = cancelToken;
              if (ct != null && ct.isCancelled) {
                throw ct.cancelError ??
                    DioException.requestCancelled(
                      requestOptions: RequestOptions(),
                      reason: 'cancelled',
                    );
              }
              debugPrint(
                '[Client] QUIC upload of "${f.name}" failed ($e) — '
                'queued for TCP',
              );
              sentPerFile[i] = 0; // restart from zero on the TCP pass
              tcpQueue.add(i);
            }
          }
        }

        await Future.wait([
          for (var k = 0; k < concurrency; k++) worker(),
        ]);
        tcpQueue.sort(); // keep the TCP pass in the user's file order
      } else {
        tcpQueue.addAll([for (var i = 0; i < files.length; i++) i]);
      }

      // ── Phase B: sequential TCP (fallbacks + zero-size files) ───────────────
      if (tcpQueue.isNotEmpty) {
        onTransport?.call('TCP');
      }
      for (final i in tcpQueue) {
        final f = files[i];
        final token = prepare.files[f.id]!; // pre-validated above

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
              // `sent` counts wire bytes (encrypted ≈ plaintext); clamp per file
              // so overall progress stays monotonic against the plaintext total.
              onSendProgress: (sent, _) {
                sentPerFile[i] = sent > f.size ? f.size : sent;
                emitOverall(i);
              },
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
        sentPerFile[i] = f.size;
        emitOverall(i);
      }
    } finally {
      // Always tear down the session's QUIC connection (success, TCP-fallback, or
      // exception) so it can't leak the endpoint/socket in Rust.
      if (_shouldUseQuic() && device.quicPort != null) {
        try {
          await quic.quicDisconnect(sessionId: prepare.sessionId);
        } on Object catch (_) {}
      }
    }
  }

  static const int _maxUploadAttempts = 3;

  /// Connect-retry budget for the initial `prepare` (fresh-install first-LAN-
  /// connection can be dropped until the OS Local Network grant lands).
  static const int _maxPrepareAttempts = 3;

  /// Cap on concurrently-sending QUIC files (Phase 2b). 4 files × up to 4
  /// streams each = 16 in-flight chunk slabs — exactly the Rust slab-pool
  /// envelope, so heavier concurrency would only queue on the pool semaphore.
  static const int _maxConcurrentQuicFiles = 4;

  /// Files at or below this size are hashed upfront (SHA-256 in prepare, cheap +
  /// verified); larger files skip it to keep "Preparing" instant.
  static const int _hashSizeLimit = 64 * 1024 * 1024; // 64 MB

  Future<void> _backoff(int attempt) =>
      Future<void>.delayed(Duration(milliseconds: 300 * attempt));

  /// Upload one file over QUIC, forwarding the Rust send stream's byte progress.
  /// Throws on any failure so [send] can fall back to the HTTP/TCP path.
  /// Upload one file over the session's already-established QUIC connection (see
  /// [quic.quicConnect] in [send]). No host/port here — the Rust side reuses the
  /// persistent connection keyed by [sessionId] and opens streams per file.
  /// Reports this FILE's cumulative bytes via [onBytes]; the caller aggregates
  /// across concurrently-sending files.
  Future<void> _uploadViaQuic(
    SendableFile f,
    String sessionId,
    DeviceInfo info, {
    required int streams,
    required int chunkSize,
    required bool resume,
    required void Function(int sentBytes) onBytes,
  }) async {
    debugPrint(
      '[Client] QUIC sending "${f.name}" (${f.size}B) via '
      '$streams stream(s), chunk ${chunkSize ~/ 1024}KB',
    );
    final sw = Stopwatch()..start();
    final stream = quic.quicSendFile(
      sessionId: sessionId,
      fileId: f.id,
      senderAlias: info.alias,
      senderFingerprint: info.fingerprint,
      filePath: f.path,
      fileName: f.name,
      fileType: f.mimeType,
      streams: streams,
      chunkSize: chunkSize,
      resume: resume,
    );
    await for (final sent in stream) {
      onBytes(sent.toInt());
    }
    sw.stop();
    // Phase 3 metrics: per-file speed + the connection's live path stats (real
    // RTT / DPLPMTUD MTU / cwnd / loss / datagram counts) for attribution.
    final secs = sw.elapsedMilliseconds / 1000;
    final mbps = secs > 0 ? f.size / (1024 * 1024) / secs : 0;
    debugPrint(
      '[Client] QUIC sent "${f.name}" '
      '${(f.size / (1024 * 1024)).toStringAsFixed(1)}MB in '
      '${sw.elapsedMilliseconds}ms = ${mbps.toStringAsFixed(1)} MB/s '
      '| ${quic.quicSessionStats(sessionId: sessionId)}',
    );
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
      yield _frame(
        (await Rust.encryptChunk(acc.toBytes(), key, index, baseNonce))!,
      );
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
