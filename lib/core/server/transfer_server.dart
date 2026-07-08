import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_multipart/shelf_multipart.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../constants/protocol.dart';
import '../identity/device_identity.dart';
import '../protocol/file_metadata.dart';
import '../protocol/file_request.dart';
import '../protocol/prepare.dart';
import '../protocol/transfer_response.dart';
import '../rust/rust_facade.dart';
import '../../src/rust/api/quic.dart' as quic;
import 'browser_share.dart';
import 'receive_naming.dart';
import 'transfer_types.dart';

/// The LAN receiver: a local HTTP server (shelf over `dart:io HttpServer`, dual
/// stack on port 58317) implementing the BIShare transfer endpoints. Mirrors the
/// native `TransferServer`.
///
/// Scaffold scope (P0): plaintext transfer path is fully wired (info/prepare/
/// upload/cancel/goodbye, accept-reject with 30s auto-reject, single-session 409,
/// PIN gate, streaming-to-disk with SHA-256 verify). The E2E-decrypt streaming
/// path is the next increment — it requires the native binary chunk-framing spec;
/// this receiver therefore returns no `publicKey` (peers send plaintext).
class TransferServer {
  TransferServer({
    required DeviceIdentity identity,
    required Directory saveDirectory,
  }) : _identity = identity,
       _saveDir = saveDirectory,
       _defaultDir = saveDirectory;

  final DeviceIdentity _identity;
  Directory _saveDir;
  final Directory _defaultDir;
  final _uuid = const Uuid();

  /// Where received files are written. Set from the "Save location" setting
  /// ('' → the default passed at construction); created if missing.
  Directory get saveDirectory => _saveDir;
  set saveDirectory(Directory dir) {
    _saveDir = dir;
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  /// Revert to the construction-time default folder ("Use default" setting).
  void resetSaveDirectory() => saveDirectory = _defaultDir;

  HttpServer? _server;

  // Settings (wired to the settings feature later).
  String? pin;
  AutoAcceptMode autoAccept = AutoAcceptMode.alwaysAsk;

  /// Web-Share (browser) state: in-memory offered files, a provider for received
  /// files (queried from drift by the DI layer), and PIN tokens minted on a
  /// correct `/verify-pin` and required by the browser list/download/upload.
  final List<BrowserFile> sharedFiles = [];
  Future<List<BrowserFile>> Function()? receivedFilesProvider;
  final Set<String> _browserTokens = {};

  /// Local instant-share tokens — a one-time (24h) or timed (5 min) link to a
  /// single file, presented as a QR a nearby device scans to download directly
  /// (no accept prompt). Mirrors native `InstantShareTokenStore`.
  final Map<String, _InstantToken> _instantTokens = {};

  /// Mint an instant-share token for [path]. One-time → 24h TTL + single use;
  /// timed → 5 min TTL, reusable. Returns the token (the caller builds the URL
  /// `http://<localIp>:${BISharePort.main}${BIShareApi.instant}?token=<token>`).
  String createInstantToken({
    required String path,
    required String fileName,
    required String mimeType,
    required bool oneTime,
  }) {
    _pruneInstantTokens();
    final token = _uuid.v4();
    _instantTokens[token] = _InstantToken(
      path: path,
      fileName: fileName,
      mimeType: mimeType,
      expires: DateTime.now().add(
        oneTime ? const Duration(hours: 24) : const Duration(minutes: 5),
      ),
      oneTime: oneTime,
    );
    return token;
  }

  void _pruneInstantTokens() {
    final now = DateTime.now();
    _instantTokens.removeWhere((_, e) => e.expires.isBefore(now));
  }

  // GET /api/v1/instant?token=  — serve a file by instant-share token.
  Future<Response> _handleInstant(Request request) async {
    _pruneInstantTokens();
    final token = request.url.queryParameters['token'];
    final entry = token == null ? null : _instantTokens[token];
    if (entry == null) {
      return _error('Link expired or invalid', BIShareStatus.notFound);
    }
    final file = File(entry.path);
    if (!file.existsSync()) {
      _instantTokens.remove(token);
      return _error('File no longer available', BIShareStatus.notFound);
    }
    // One-time links are consumed before streaming (race-safe).
    if (entry.oneTime) _instantTokens.remove(token);
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': entry.mimeType.isNotEmpty
            ? entry.mimeType
            : (lookupMimeType(entry.fileName) ?? 'application/octet-stream'),
        'content-length': '${file.lengthSync()}',
        'content-disposition':
            'attachment; filename="${_headerSafe(entry.fileName)}"',
        'access-control-allow-origin': '*',
      },
    );
  }

  /// When hidden, `/api/v1/info` returns 403 so probing peers drop us (mirrors
  /// native "Hidden" visibility). Discovery advertisement is also stopped.
  bool hidden = false;

  /// Favorites hooks (set from the favorites feature): whether a sender is a
  /// favorite, and whether that favorite is marked to auto-accept.
  bool Function(String fingerprint)? isFavorite;
  bool Function(String fingerprint)? favoriteAutoAccepts;

  final Map<String, TransferSession> _sessions = {};

  final _incoming = StreamController<PendingTransfer>.broadcast();
  final _incomingRequests = StreamController<PendingFileRequest>.broadcast();
  final _progress = StreamController<ReceiveProgress>.broadcast();
  final _received = StreamController<ReceivedFile>.broadcast();
  final _goodbyes = StreamController<String>.broadcast();

  /// Incoming transfers awaiting an accept/reject decision.
  Stream<PendingTransfer> get incoming => _incoming.stream;

  /// Incoming file-requests (reverse flow) awaiting a decision.
  Stream<PendingFileRequest> get incomingRequests => _incomingRequests.stream;

  /// Live receive progress.
  Stream<ReceiveProgress> get progress => _progress.stream;

  /// Files that finished downloading.
  Stream<ReceivedFile> get received => _received.stream;

  /// Fingerprints of peers that announced they are going offline.
  Stream<String> get goodbyes => _goodbyes.stream;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    // Testing hook: BISHARE_AUTO_ACCEPT=1 makes the receiver accept without a
    // prompt so interop transfers can be driven hands-free. Off by default.
    if (Platform.environment['BISHARE_AUTO_ACCEPT'] == '1') {
      autoAccept = AutoAcceptMode.acceptAll;
      debugPrint('[Server] AUTO-ACCEPT enabled (env)');
    }
    if (!_saveDir.existsSync()) _saveDir.createSync(recursive: true);
    debugPrint(
      '[Server] listening on :${BISharePort.main}, saving to ${_saveDir.path}',
    );
    final router = Router()
      ..get(BIShareApi.info, _handleInfo)
      ..post(BIShareApi.prepare, _handlePrepare)
      ..post(BIShareApi.upload, _handleUpload)
      ..post(BIShareApi.cancel, _handleCancel)
      ..post(BIShareApi.goodbye, _handleGoodbye)
      ..post(BIShareApi.request, _handleFileRequest)
      ..get(BIShareApi.instant, _handleInstant)
      // Web-Share browser UI + endpoints.
      ..get('/', _handleBrowserPage)
      ..post(BIShareApi.verifyPin, _handleVerifyPin)
      ..get(BIShareApi.files, _guardPin(_handleFileList))
      ..get(BIShareApi.download, _guardPin(_handleDownload))
      ..get(BIShareApi.downloadAll, _guardPin(_handleDownloadAll))
      ..post(BIShareApi.browserUpload, _guardPin(_handleBrowserUpload));

    final handler = const Pipeline()
        .addMiddleware(_logRequests())
        .addHandler(router.call);

    // Dual-stack bind so both IPv4 and IPv6 peers can reach us.
    _server = await HttpServer.bind(
      InternetAddress.anyIPv6,
      BISharePort.main,
      v6Only: false,
      shared: true,
    );
    shelf_io.serveRequests(_server!, handler);
    _startQuic();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    await _quicSub?.cancel();
    _quicSub = null;
    quic.quicStop(port: BISharePort.quic);
    _sessions.clear();
  }

  // ---- QUIC receiver (fast transport; TLS 1.3, no app-layer E2E) ----

  StreamSubscription<quic.QuicServerEvent>? _quicSub;

  /// Start the QUIC server alongside the TCP one. It stages received files as
  /// `.part` temps; [_finalizeQuic] names/moves/records them like the TCP path.
  void _startQuic() {
    _quicSub?.cancel();
    _quicSub =
        quic.quicServe(port: BISharePort.quic, saveDir: _saveDir.path).listen(
      _onQuicEvent,
      onError: (Object e) => debugPrint('[Server] QUIC stream error: $e'),
    );
  }

  void _onQuicEvent(quic.QuicServerEvent event) {
    switch (event) {
      case quic.QuicServerEvent_Ready():
        debugPrint('[Server] QUIC listening on :${BISharePort.quic}');
      case quic.QuicServerEvent_Progress(
        :final sessionId,
        :final fileName,
        :final received,
        :final total,
      ):
        final session = _sessions[sessionId];
        if (session != null) {
          // Keep the session alive so a long QUIC transfer doesn't idle-expire
          // (which would drop the sender identity), and drive the progress card.
          session.lastActivity = DateTime.now();
          _emitProgress(
            session,
            fileName,
            _sessionBytes(session) + received.toInt(),
          );
        } else {
          // Session idle-expired — emit a minimal progress so the card still
          // advances instead of sitting on "Starting…".
          _progress.add(
            ReceiveProgress(
              sessionId: sessionId,
              senderAlias: '',
              totalFiles: 1,
              completedFiles: 0,
              currentFileName: fileName,
              bytesReceived: received.toInt(),
              totalBytes: total.toInt(),
            ),
          );
        }
      case quic.QuicServerEvent_Error(:final message):
        debugPrint('[Server] QUIC error: $message');
      case quic.QuicServerEvent_Received(
        :final sessionId,
        :final fileId,
        :final senderAlias,
        :final senderFingerprint,
        :final fileName,
        :final fileType,
        :final tempPath,
        :final size,
      ):
        _finalizeQuic(
          sessionId,
          fileId,
          senderAlias,
          senderFingerprint,
          fileName,
          fileType,
          tempPath,
          size.toInt(),
        );
    }
  }

  /// Finalise a QUIC-received `.part` file: smart-name it, move it into place, and
  /// emit a [ReceivedFile] + progress — mirroring the TCP upload completion.
  Future<void> _finalizeQuic(
    String sessionId,
    String fileId,
    String senderAlias,
    String senderFingerprint,
    String fileName,
    String fileType,
    String tempPath,
    int size,
  ) async {
    final tmp = File(tempPath);
    if (!tmp.existsSync()) return;
    final session = _sessions[sessionId];
    final meta =
        session?.files[fileId] ??
        FileMetadata(
          id: fileId,
          fileName: fileName,
          size: size,
          fileType: fileType,
        );
    // Sender identity comes over the wire (the TCP session may have idle-expired
    // during a long QUIC transfer), falling back to the session then a generic.
    final alias = senderAlias.isNotEmpty
        ? senderAlias
        : (session?.sender.alias ?? 'Nearby device');
    final fingerprint = senderFingerprint.isNotEmpty
        ? senderFingerprint
        : session?.sender.fingerprint;
    final saved = ReceiveNaming.targetFile(_saveDir, meta, alias);
    try {
      await tmp.rename(saved.path);
    } on FileSystemException {
      await tmp.copy(saved.path);
      if (tmp.existsSync()) tmp.deleteSync();
    }
    debugPrint(
      '[Server] QUIC received "${meta.fileName}" (${size}B) → ${saved.path}',
    );
    _received.add(
      ReceivedFile(
        fileName: saved.uri.pathSegments.last,
        savedPath: saved.path,
        size: size,
        senderAlias: alias,
        senderFingerprint: fingerprint,
        fileType: meta.fileType,
        encrypted: false, // QUIC = TLS transport encryption, no app-layer E2E
        receivedAt: DateTime.now(),
        verified: true,
      ),
    );
    if (session != null) {
      session.completedFileIds.add(fileId);
      _emitProgress(
        session,
        meta.fileName,
        _sessionBytes(session),
        complete: session.isComplete,
      );
      if (session.isComplete) _sessions.remove(sessionId);
    }
  }

  /// Ingest a file received over an out-of-band transport (offline Nearby /
  /// MultipeerConnectivity). The native plugin streams it to [tempPath]; here we
  /// move it into the save directory with the standard naming and emit it through
  /// the SAME [received] stream that history + inbox consume — so a Nearby receive
  /// behaves exactly like a LAN one (no duplicated save/history logic).
  Future<ReceivedFile?> ingestExternalFile({
    required String tempPath,
    required String fileName,
    required String fileType,
    required int size,
    required String senderAlias,
    String? senderFingerprint,
  }) async {
    final tmp = File(tempPath);
    if (!tmp.existsSync()) return null;
    final meta = FileMetadata(
      id: _uuid.v4(),
      fileName: fileName,
      size: size,
      fileType: fileType,
    );
    final saved = ReceiveNaming.targetFile(_saveDir, meta, senderAlias);
    try {
      await tmp.rename(saved.path);
    } on FileSystemException {
      await tmp.copy(saved.path);
      if (tmp.existsSync()) tmp.deleteSync();
    }
    debugPrint(
      '[Server] Nearby received "$fileName" (${size}B) → ${saved.path}',
    );
    final received = ReceivedFile(
      fileName: saved.uri.pathSegments.last,
      savedPath: saved.path,
      size: size,
      senderAlias: senderAlias,
      senderFingerprint: senderFingerprint,
      fileType: fileType,
      encrypted: false,
      receivedAt: DateTime.now(),
      verified: true,
    );
    _received.add(received);
    return received;
  }

  // GET /api/v1/info
  Future<Response> _handleInfo(Request request) async {
    if (hidden) return _error('Device is hidden', BIShareStatus.forbidden);
    final info = await _identity.makeDeviceInfo();
    return _json(info.toJson());
  }

  // POST /api/v1/prepare
  Future<Response> _handlePrepare(Request request) async {
    final PrepareRequest prepareReq;
    try {
      final body = await request.readAsString();
      prepareReq = PrepareRequest.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    } on Object {
      return _error('Invalid request body', BIShareStatus.serverError);
    }

    // PIN gate.
    if (pin != null && pin!.isNotEmpty) {
      final provided = request.url.queryParameters['pin'];
      if (provided == null) {
        return _error('PIN required', BIShareStatus.pinRequired);
      }
      if (provided != pin) {
        return _error('Wrong PIN', BIShareStatus.forbidden);
      }
    }

    _reapIdleSessions();
    if (_sessions.isNotEmpty) {
      return _error('Device busy', BIShareStatus.busy);
    }

    // E2E: derive the shared key from the sender's public key (symmetric with the
    // key the sender derives from ours). Null → plaintext session.
    final senderPub = prepareReq.info.publicKey;
    final symmetricKey = (senderPub != null && senderPub.isNotEmpty)
        ? _identity.deriveKey(senderPub)
        : null;
    debugPrint(
      '[Server] prepare from "${prepareReq.info.alias}" (${prepareReq.info.deviceModel}) '
      '${prepareReq.files.length} file(s), e2e=${symmetricKey != null}',
    );

    final sessionId = _uuid.v4();
    final tokens = {for (final id in prepareReq.files.keys) id: _uuid.v4()};
    final session = TransferSession(
      sessionId: sessionId,
      sender: prepareReq.info,
      files: prepareReq.files,
      tokens: tokens,
      createdAt: DateTime.now(),
      symmetricKey: symmetricKey,
    );

    final accepted = await _decide(session);
    if (!accepted) {
      return _error('Transfer rejected', BIShareStatus.forbidden);
    }

    _sessions[sessionId] = session;
    _emitProgress(session, '', 0);

    final response = PrepareResponse(
      sessionId: sessionId,
      files: tokens,
      // Advertising our public key tells the sender to E2E-encrypt the upload.
      publicKey: symmetricKey != null ? _identity.publicKeyBase64 : null,
      maxConcurrent:
          BIShareConfig.versionAtLeast(
            prepareReq.info.version,
            BIShareConfig.speedProtocolMinVersion,
          )
          ? BIShareConfig.defaultMaxConcurrentV2
          : BIShareConfig.defaultMaxConcurrent,
      keepAlive: true,
    );
    return _json(response.toJson());
  }

  /// Auto-accept or surface a [PendingTransfer] and wait (30s auto-reject).
  Future<bool> _decide(TransferSession session) async {
    if (autoAccept == AutoAcceptMode.acceptAll) return true;
    final fp = session.sender.fingerprint;
    // Per-device auto-accept (a favorite marked "auto-accept") always wins.
    if (favoriteAutoAccepts?.call(fp) ?? false) return true;
    // "Favorites only" auto-accepts known favorites; everyone else is prompted.
    if (autoAccept == AutoAcceptMode.favoritesOnly &&
        (isFavorite?.call(fp) ?? false)) {
      return true;
    }
    final pending = PendingTransfer(session: session);
    _incoming.add(pending);
    try {
      return await pending.decision.future.timeout(
        BIShareConfig.acceptRejectTimeout,
        onTimeout: () => false,
      );
    } on TimeoutException {
      return false;
    } finally {
      pending.reject(); // no-op if already decided; unblocks any waiter
    }
  }

  // POST /api/v1/upload?sessionId=&fileId=&token=
  Future<Response> _handleUpload(Request request) async {
    final q = request.url.queryParameters;
    final sessionId = q['sessionId'];
    final fileId = q['fileId'];
    final token = q['token'];
    if (sessionId == null || fileId == null || token == null) {
      return _error('Missing upload parameters', BIShareStatus.serverError);
    }
    final session = _sessions[sessionId];
    if (session == null) return _error('No session', BIShareStatus.notFound);
    if (session.tokens[fileId] != token) {
      return _error('Bad token', BIShareStatus.forbidden);
    }
    final meta = session.files[fileId];
    if (meta == null) return _error('Unknown file', BIShareStatus.notFound);

    session.lastActivity = DateTime.now();

    // E2E: a `X-Encrypted: chunked` body is a stream of
    //   [uint32 BE length][ nonce(12) | ciphertext | tag(16) ]
    // frames (plaintext chunk ≤ 256 KB each). We decrypt each frame straight to
    // disk (ciphertext never persisted) and hash the PLAINTEXT for verification.
    final isEncrypted =
        session.encrypted && request.headers['x-encrypted'] == 'chunked';

    // Stream body → temp file while hashing (no full-file buffering).
    final tmp = File('${_saveDir.path}/.${_uuid.v4()}.part');
    final out = tmp.openWrite();
    // Hash only the PLAINTEXT path (where the SHA is the sole integrity check).
    // For encrypted transfers the per-chunk AES-256-GCM tag already authenticates
    // every chunk (decrypt throws on tamper) and the index-bound nonce + TCP
    // ordering reject reorder/replay — so the end-to-end SHA is redundant, and
    // running pure-Dart SHA-256 per chunk on the receiver's isolate is the single
    // biggest speed cost (worst on slower CPUs). Matches the native receiver,
    // which reports verified for encrypted transfers without re-hashing.
    final needHash = meta.sha256 != null && !isEncrypted;
    final digestCapture = _DigestCapture();
    final hasher = needHash
        ? sha256.startChunkedConversion(digestCapture)
        : null;
    var bytes = 0;
    // Throttle progress to ~12/s. Emitting per network read (hundreds/s) causes
    // a rebuild storm that janks the receiver UI (worst on a tab switch).
    var lastEmitMs = 0;
    void emitThrottled() {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastEmitMs < 80) return;
      lastEmitMs = now;
      _emitProgress(session, meta.fileName, _sessionBytes(session) + bytes);
    }

    try {
      if (isEncrypted) {
        final key = session.symmetricKey!;
        const maxFrame =
            BIShareConfig.maxChunkSize + BIShareCrypto.gcmOverheadPerChunk;
        // Fixed scratch buffer + read/write cursors, NOT a per-read
        // BytesBuilder.takeBytes(): takeBytes() re-materialised the entire
        // pending accumulator on every ~64KB network read (64K+128K+…+1M ≈
        // 8.5 MB copied per 1 MB frame — an O(n²) the 1 MB chunk bump made
        // strictly worse). Here each read is appended into a preallocated
        // buffer and frames are parsed in place; only the small partial-frame
        // remainder is ever moved (compaction).
        var scratch = Uint8List(maxFrame * 2);
        var writePos = 0; // bytes buffered so far
        var readPos = 0; // bytes already consumed into frames
        var index = 0;
        Uint8List? baseNonce;
        await for (final chunk in request.read()) {
          bytes += chunk.length;
          // Make room: drop the consumed prefix, then grow only if a single
          // in-flight frame plus this read still won't fit (pathological).
          if (writePos + chunk.length > scratch.length) {
            if (readPos > 0) {
              scratch.setRange(0, writePos - readPos, scratch, readPos);
              writePos -= readPos;
              readPos = 0;
            }
            if (writePos + chunk.length > scratch.length) {
              final bigger = Uint8List(writePos + chunk.length);
              bigger.setRange(0, writePos, scratch);
              scratch = bigger;
            }
          }
          scratch.setRange(writePos, writePos + chunk.length, chunk);
          writePos += chunk.length;

          // Parse every complete frame currently buffered.
          while (writePos - readPos >= 4) {
            final len =
                (scratch[readPos] << 24) |
                (scratch[readPos + 1] << 16) |
                (scratch[readPos + 2] << 8) |
                scratch[readPos + 3];
            if (len <= 0 || len > maxFrame) {
              throw const FormatException('invalid encrypted frame length');
            }
            if (writePos - readPos - 4 < len) break; // wait for the rest
            final encChunk = Uint8List.sublistView(
              scratch,
              readPos + 4,
              readPos + 4 + len,
            );
            // chunk 0's embedded nonce IS the base nonce (index XOR 0).
            baseNonce ??= Uint8List.fromList(
              encChunk.sublist(0, BIShareCrypto.gcmNonceSize),
            );
            // `await` → decrypt runs on FRB's Rust worker pool; the kernel keeps
            // filling the socket recv buffer during AES (recv↔decrypt overlap).
            // FRB copies `encChunk` into the wire buffer synchronously here, and
            // `await for` pauses the subscription while the body runs, so the
            // scratch view stays valid across the await.
            final dec = await Rust.decryptChunk(encChunk, key, index, baseNonce);
            if (dec == null) {
              throw const FormatException('chunk decryption failed');
            }
            out.add(dec);
            hasher?.add(dec);
            readPos += 4 + len;
            index++;
          }
          // A concurrent /api/v1/cancel may have removed the session; stop
          // emitting so a stray partial can't re-show a just-cleared card.
          if (!_sessions.containsKey(sessionId)) {
            throw const _AbortedException();
          }
          emitThrottled();
        }
        if (writePos != readPos) {
          throw const FormatException('truncated encrypted upload');
        }
      } else {
        await for (final chunk in request.read()) {
          out.add(chunk);
          hasher?.add(chunk);
          bytes += chunk.length;
          if (!_sessions.containsKey(sessionId)) {
            throw const _AbortedException();
          }
          emitThrottled();
        }
      }
      await out.close();
      hasher?.close();
    } on Object {
      await out.close();
      if (tmp.existsSync()) tmp.deleteSync();
      // Sender aborted (cancel) or the stream errored. Drop the session and emit
      // a terminal "complete" progress so the receiver's progress card clears
      // immediately instead of hanging on a partial transfer — we do NOT rely
      // solely on the sender's separate /api/v1/cancel arriving.
      _sessions.remove(sessionId);
      _emitProgress(session, '', 0, complete: true);
      return _error('Upload failed', BIShareStatus.serverError);
    }

    final digest = digestCapture.value;
    // When we didn't hash (encrypted → GCM-authenticated, or no checksum sent)
    // the transfer is considered verified; otherwise compare the plaintext SHA.
    final verified = !needHash || meta.sha256 == digest?.toString();
    if (!verified) {
      if (tmp.existsSync()) tmp.deleteSync();
      // Drop the session + clear progress so a checksum failure doesn't wedge
      // the receiver as "busy" until the idle-reaper runs.
      _sessions.remove(sessionId);
      _emitProgress(session, '', 0, complete: true);
      return _json(
        const UploadResponse(success: false, verified: false).toJson(),
      );
    }

    final saved = ReceiveNaming.targetFile(
      _saveDir,
      meta,
      session.sender.alias,
    );
    // rename() fails across volumes (EXDEV) — likely with a custom save location
    // on another disk — so fall back to copy+delete.
    try {
      await tmp.rename(saved.path);
    } on FileSystemException {
      await tmp.copy(saved.path);
      if (tmp.existsSync()) tmp.deleteSync();
    }

    session.completedFileIds.add(fileId);
    debugPrint(
      '[Server] received "${meta.fileName}" (${meta.size}B, e2e=$isEncrypted, '
      'sha256-ok=$verified) → ${saved.path}',
    );
    _received.add(
      ReceivedFile(
        fileName: saved.uri.pathSegments.last,
        savedPath: saved.path,
        size: meta.size,
        senderAlias: session.sender.alias,
        senderFingerprint: session.sender.fingerprint,
        fileType: meta.fileType,
        encrypted: isEncrypted,
        receivedAt: DateTime.now(),
        verified: verified,
      ),
    );
    _emitProgress(
      session,
      meta.fileName,
      _sessionBytes(session),
      complete: session.isComplete,
    );
    if (session.isComplete) _sessions.remove(sessionId);

    return _json(
      UploadResponse(
        success: true,
        verified: true,
        encrypted: isEncrypted,
      ).toJson(),
    );
  }

  // POST /api/v1/cancel?sessionId=
  Future<Response> _handleCancel(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId != null) {
      final session = _sessions.remove(sessionId);
      if (session != null) {
        _progress.add(
          ReceiveProgress(
            sessionId: sessionId,
            senderAlias: session.sender.alias,
            totalFiles: session.files.length,
            completedFiles: session.completedFileIds.length,
            currentFileName: '',
            bytesReceived: 0,
            totalBytes: session.files.values.fold(0, (s, f) => s + f.size),
            isComplete: true,
          ),
        );
      }
    }
    return _json(const {'success': true});
  }

  // POST /api/v1/goodbye  { "fingerprint": "..." }
  Future<Response> _handleGoodbye(Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final fp = (body as Map<String, dynamic>)['fingerprint'] as String?;
      if (fp != null) _goodbyes.add(fp);
    } on Object {
      // ignore malformed goodbye
    }
    return _json(const {'success': true});
  }

  // POST /api/v1/request — reverse flow: a peer asks US to send it files. We
  // surface a prompt, hold the connection, and reply accepted/declined. On
  // accept the UI sends files back to the requester via the normal path.
  Future<Response> _handleFileRequest(Request request) async {
    final FileRequestMessage msg;
    try {
      msg = FileRequestMessage.fromJson(
        jsonDecode(await request.readAsString()) as Map<String, dynamic>,
      );
    } on Object {
      return _error('Invalid request', BIShareStatus.serverError);
    }
    debugPrint(
      '[Server] file request from "${msg.requesterAlias}": '
      '${msg.message?.isNotEmpty == true ? msg.message : "(no message)"}',
    );
    final pending = PendingFileRequest(request: msg);
    _incomingRequests.add(pending);
    // Auto-decline after 60s (matches native) so the sender isn't left hanging.
    final accepted = await pending.decision.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => false,
    );
    return _json(
      FileRequestResponse(requestId: msg.requestId, accepted: accepted).toJson(),
    );
  }

  // ---- Web-Share (browser) ----

  /// Combined browser file list: in-memory offers, then received files.
  Future<List<BrowserFile>> _browserFiles() async {
    final received = await receivedFilesProvider?.call() ?? const [];
    return [...sharedFiles, ...received];
  }

  /// Wraps a handler with the browser PIN gate (open when no PIN is set).
  Handler _guardPin(Handler inner) => (request) async {
    if (pin == null || pin!.isEmpty) return inner(request);
    final token =
        request.url.queryParameters['token'] ?? request.headers['x-pin-token'];
    if (token != null && _browserTokens.contains(token)) return inner(request);
    return _error('PIN required', BIShareStatus.pinRequired);
  };

  // GET / — the browser Web-Share page.
  Future<Response> _handleBrowserPage(Request request) async {
    if (hidden) return _error('Device is hidden', BIShareStatus.forbidden);
    final info = await _identity.makeDeviceInfo();
    return Response.ok(
      browserPageHtml(
        alias: info.alias,
        pinEnabled: pin != null && pin!.isNotEmpty,
      ),
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  // POST /api/v1/verify-pin?pin=
  Future<Response> _handleVerifyPin(Request request) async {
    if (pin == null || pin!.isEmpty) return _json({'verified': true});
    if (request.url.queryParameters['pin'] == pin) {
      final token = _uuid.v4();
      _browserTokens.add(token);
      return _json({'verified': true, 'token': token});
    }
    return _error('Wrong PIN', BIShareStatus.forbidden);
  }

  // GET /api/v1/files
  Future<Response> _handleFileList(Request request) async {
    final files = await _browserFiles();
    return _json([
      for (var i = 0; i < files.length; i++)
        {
          'index': i,
          'fileName': files[i].fileName,
          'fileType': files[i].fileType,
          'size': files[i].size,
        },
    ]);
  }

  // GET /api/v1/download?index=N
  Future<Response> _handleDownload(Request request) async {
    final idx = int.tryParse(request.url.queryParameters['index'] ?? '');
    if (idx == null) return _error('Missing index', BIShareStatus.serverError);
    final files = await _browserFiles();
    if (idx < 0 || idx >= files.length) {
      return _error('Not found', BIShareStatus.notFound);
    }
    final f = files[idx];
    final file = File(f.path);
    if (!file.existsSync()) return _error('File gone', BIShareStatus.notFound);
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': f.fileType.isNotEmpty
            ? f.fileType
            : (lookupMimeType(f.fileName) ?? 'application/octet-stream'),
        'content-length': '${file.lengthSync()}',
        'content-disposition':
            'attachment; filename="${_headerSafe(f.fileName)}"',
        'access-control-allow-origin': '*',
      },
    );
  }

  // GET /api/v1/download-all — a ZIP of every available file.
  Future<Response> _handleDownloadAll(Request request) async {
    final files = await _browserFiles();
    final present = files.where((f) => File(f.path).existsSync()).toList();
    if (present.isEmpty) return _error('No files', BIShareStatus.notFound);
    final tmp = File('${_saveDir.path}/.bishare-${_uuid.v4()}.zip');
    final encoder = ZipFileEncoder()..create(tmp.path);
    try {
      for (final f in present) {
        await encoder.addFile(File(f.path), f.fileName);
      }
      await encoder.close();
    } on Object {
      await encoder.close();
      if (tmp.existsSync()) tmp.deleteSync();
      return _error('Zip failed', BIShareStatus.serverError);
    }
    Stream<List<int>> body() async* {
      try {
        yield* tmp.openRead();
      } finally {
        if (tmp.existsSync()) tmp.deleteSync();
      }
    }

    return Response.ok(
      body(),
      headers: {
        'content-type': 'application/zip',
        'content-length': '${tmp.lengthSync()}',
        'content-disposition': 'attachment; filename="BIShare-Files.zip"',
        'access-control-allow-origin': '*',
      },
    );
  }

  // POST /api/v1/browser-upload — multipart file upload from a browser.
  Future<Response> _handleBrowserUpload(Request request) async {
    final form = request.formData();
    if (form == null) return _error('Not multipart', BIShareStatus.serverError);
    var saved = 0;
    await for (final part in form.formData) {
      final filename = part.filename;
      if (filename == null) continue;
      final meta = FileMetadata(
        id: _uuid.v4(),
        fileName: filename,
        size: 0,
        fileType: lookupMimeType(filename) ?? 'application/octet-stream',
      );
      final target = ReceiveNaming.targetFile(_saveDir, meta, 'Browser');
      final sink = target.openWrite();
      await sink.addStream(part.part);
      await sink.close();
      final size = target.lengthSync();
      _received.add(
        ReceivedFile(
          fileName: target.uri.pathSegments.last,
          savedPath: target.path,
          size: size,
          senderAlias: 'Browser',
          senderFingerprint: '',
          fileType: meta.fileType,
          receivedAt: DateTime.now(),
          verified: true,
        ),
      );
      saved++;
    }
    return _json({'success': true, 'saved': saved});
  }

  static String _headerSafe(String name) =>
      name.replaceAll('"', '').replaceAll(RegExp('[\r\n]'), '');

  // ---- helpers ----

  int _sessionBytes(TransferSession s) => s.files.entries
      .where((e) => s.completedFileIds.contains(e.key))
      .fold<int>(0, (sum, e) => sum + e.value.size);

  void _emitProgress(
    TransferSession s,
    String currentFile,
    int bytesReceived, {
    bool complete = false,
  }) {
    _progress.add(
      ReceiveProgress(
        sessionId: s.sessionId,
        senderAlias: s.sender.alias,
        totalFiles: s.files.length,
        completedFiles: s.completedFileIds.length,
        currentFileName: currentFile,
        bytesReceived: bytesReceived,
        totalBytes: s.files.values.fold(0, (sum, f) => sum + f.size),
        isComplete: complete,
      ),
    );
  }

  void _reapIdleSessions() {
    final now = DateTime.now();
    _sessions.removeWhere(
      (_, s) =>
          now.difference(s.lastActivity) > const Duration(seconds: 30) ||
          now.difference(s.createdAt) > const Duration(minutes: 5),
    );
  }

  Response _json(Object data, {int status = BIShareStatus.ok}) => Response(
    status,
    body: jsonEncode(data),
    headers: {'content-type': 'application/json'},
  );

  Response _error(String message, int status) =>
      _json({'message': message}, status: status);

  Middleware _logRequests() =>
      (inner) =>
          (request) async => inner(request);

  Future<void> dispose() async {
    await stop();
    await _incoming.close();
    await _incomingRequests.close();
    await _progress.close();
    await _received.close();
    await _goodbyes.close();
  }
}

/// Thrown to unwind the upload loop when the session was cancelled mid-stream.
class _AbortedException implements Exception {
  const _AbortedException();
}

/// A local instant-share token entry (see [TransferServer.createInstantToken]).
class _InstantToken {
  _InstantToken({
    required this.path,
    required this.fileName,
    required this.mimeType,
    required this.expires,
    required this.oneTime,
  });

  final String path;
  final String fileName;
  final String mimeType;
  final DateTime expires;
  final bool oneTime;
}

/// Captures the final SHA-256 digest from a chunked conversion.
class _DigestCapture implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
