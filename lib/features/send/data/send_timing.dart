import 'package:flutter/foundation.dart';

/// Where the time of a send goes (transfer-quality-plan.md, Phase 0): Photos
/// export, hashing, the offer round trip, each file's upload. Off unless the
/// build sets `--dart-define=BISHARE_TIMING=true`; then each line is printed
/// with a `[Timing]` tag (logcat / Xcode console).
class SendTiming {
  SendTiming._();

  static const bool enabled = bool.fromEnvironment('BISHARE_TIMING');

  static void log(String line) {
    if (enabled) debugPrint('[Timing] $line');
  }

  /// Runs [body] and logs how long it took under [label].
  static Future<T> time<T>(String label, Future<T> Function() body) async {
    if (!enabled) return body();
    final sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      log('$label ${sw.elapsedMilliseconds} ms');
    }
  }

  /// "12.3 MB/s" for [bytes] over [ms].
  static String rate(int bytes, int ms) =>
      ms <= 0 ? '-' : '${(bytes / 1e6 / (ms / 1000)).toStringAsFixed(1)} MB/s';
}
