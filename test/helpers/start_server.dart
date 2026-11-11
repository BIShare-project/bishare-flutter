import 'dart:io';

import 'package:bishare/core/server/transfer_server.dart';

/// Starts [server] on the fixed LAN port, waiting while another test file
/// running in parallel holds it (`flutter test` runs files concurrently, and
/// the receiver always binds BISharePort.main).
Future<void> startServerWhenFree(
  TransferServer server, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final until = DateTime.now().add(timeout);
  while (true) {
    try {
      await server.start();
      return;
    } on SocketException {
      await server.stop();
      if (DateTime.now().isAfter(until)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
