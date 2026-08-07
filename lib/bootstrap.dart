import 'package:flutter/foundation.dart';

import 'core/bench.dart';
import 'core/desktop/desktop_service.dart';
import 'core/di/locator.dart';
import 'core/rust/rust_facade.dart';
import 'core/server/transfer_server.dart';
import 'features/discovery/data/discovery_service.dart';

/// One-time app initialisation: load the Rust bridge, build the DI graph, then
/// start the receiver server and discovery. Failures to bind/advertise are
/// non-fatal — the UI still runs.
Future<void> bootstrap() async {
  // Loading the Rust bridge is best-effort: on a broken/compat runtime where the
  // native library can't load, we log and continue so the app still LAUNCHES and
  // renders (transfer crypto degrades — see DeviceIdentity.rustEngine). A failure
  // here must never leave the user staring at a blank window.
  try {
    await Rust.ensureInitialized();
  } on Object catch (e) {
    debugPrint('[bootstrap] Rust bridge init failed (crypto degraded): $e');
  }
  await setupLocator();
  try {
    await getIt<TransferServer>().start();
  } on Object catch (e) {
    debugPrint('[bootstrap] server start failed: $e');
  }
  try {
    await getIt<DiscoveryService>().start();
  } on Object catch (e) {
    debugPrint('[bootstrap] discovery start failed: $e');
  }

  // Inbound goodbye → drop the peer from discovery immediately (don't wait for
  // the stale sweep).
  getIt<TransferServer>().goodbyes.listen(
    getIt<DiscoveryService>().removeByFingerprint,
  );

  // Desktop-only: menu-bar/tray + hide-to-tray + autostart (no-op elsewhere).
  try {
    await getIt<DesktopService>().start();
  } on Object catch (e) {
    debugPrint('[bootstrap] desktop init failed: $e');
  }

  // Dev-only throughput benchmark (no-op unless BISHARE_BENCH=1).
  await runLoopbackBenchIfRequested();
}
