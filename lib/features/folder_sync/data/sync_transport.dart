/// Production transports for [SyncEngine] — the pieces tests inject fakes for.
library;

import 'dart:io';
import 'dart:typed_data';

import '../../../core/storage/app_database.dart';
import '../../../core/sync/sync_paths.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../send/data/transfer_client.dart';
import '../../send/domain/sendable_file.dart';
import 'sync_engine.dart';
import 'sync_wire.dart';

/// POSTs one encrypted sync body with a bare [HttpClient] (no dio pipeline —
/// binary in, binary out, tight timeouts).
SyncPoster httpSyncPoster() {
  return (Uri url, Uint8List body, Map<String, String> headers) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.postUrl(url);
      headers.forEach(req.headers.set);
      req.headers.contentType = ContentType.binary;
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(const Duration(seconds: 60));
      final builder = BytesBuilder(copy: false);
      await for (final chunk in res) {
        builder.add(chunk);
      }
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('sync exchange HTTP ${res.statusCode}', uri: url);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  };
}

/// Pushes needed files through the normal transfer pipeline (prepare/upload,
/// E2E, TCP for M1) with the sync routing fields set — full reuse, zero new
/// upload machinery.
SyncPayloadSender transferPayloadSender(TransferClient client) {
  return (
    SyncPair pair,
    List<SyncNeededFile> needed,
    String host,
    int port, {
    void Function(int done, int total)? onFile,
  }) async {
    final files = <SendableFile>[];
    final relPaths = <String, String>{};
    for (var i = 0; i < needed.length; i++) {
      final n = needed[i];
      final abs = safeSyncJoin(pair.rootPath, n.path);
      if (abs == null || !File(abs).existsSync()) continue; // vanished mid-sync
      final id = 'sync-$i';
      files.add(SendableFile.fromPath(abs, id: id));
      relPaths[id] = n.path;
    }
    if (files.isEmpty) return;

    final now = DateTime.now();
    await client.send(
      files,
      DiscoveredDevice(
        fingerprint: pair.peerFingerprint,
        alias: pair.peerFingerprint,
        host: host,
        port: port,
        lastSeen: now,
        firstSeen: now,
      ),
      syncPairId: pair.id,
      syncRelPaths: relPaths,
      onProgress: (index, total, name, sent, totalBytes) =>
          onFile?.call(index, total),
    );
  };
}
