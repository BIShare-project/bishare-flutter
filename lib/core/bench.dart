import 'dart:io';

import 'package:flutter/foundation.dart';

import '../features/discovery/domain/discovered_device.dart';
import '../features/send/data/transfer_client.dart';
import '../features/send/domain/sendable_file.dart';
import 'constants/protocol.dart';
import 'di/locator.dart';
import 'server/transfer_server.dart';
import 'server/transfer_types.dart';

/// Dev-only throughput benchmark, gated behind `BISHARE_BENCH=1`. Sends a large
/// file to this app's own receiver over loopback (real encrypt→frame→socket→
/// deframe→decrypt→disk path) and prints MB/s. Measure in **release**
/// (`BISHARE_BENCH=1 flutter run --release -d macos`) — the ≥40 MB/s P0 gate is a
/// release criterion; debug builds ship an unoptimised AES-GCM.
Future<void> runLoopbackBenchIfRequested() async {
  if (Platform.environment['BISHARE_BENCH'] != '1') return;

  getIt<TransferServer>().autoAccept = AutoAcceptMode.acceptAll;
  final client = getIt<TransferClient>();

  final dir = await Directory.systemTemp.createTemp('bishare_bench');
  const total = 128 * 1024 * 1024;
  final src = File('${dir.path}/payload.bin');
  final sink = src.openWrite();
  final block = Uint8List(1024 * 1024);
  for (var w = 0; w < total; w += block.length) {
    sink.add(block);
  }
  await sink.close();

  final device = DiscoveredDevice(
    fingerprint: 'bench-loop',
    alias: 'bench-loop',
    host: '127.0.0.1',
    port: BISharePort.main,
    lastSeen: DateTime.now(),
  );
  final file = SendableFile(
    id: 'bench',
    path: src.path,
    name: 'payload.bin',
    size: total,
    mimeType: 'application/octet-stream',
  );

  final sw = Stopwatch()..start();
  try {
    await client.send([file], device);
    sw.stop();
    final mbps = total / (1024 * 1024) / (sw.elapsedMilliseconds / 1000);
    debugPrint(
      'BISHARE_BENCH RESULT: ${mbps.toStringAsFixed(1)} MB/s '
      '(128 MB encrypted in ${sw.elapsedMilliseconds} ms) '
      '${mbps >= 40 ? "PASS >=40" : "BELOW 40"}',
    );
  } on Object catch (e) {
    debugPrint('BISHARE_BENCH ERROR: $e');
  } finally {
    await dir.delete(recursive: true);
  }
}
