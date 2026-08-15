import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/build_flags.dart';
import '../constants/cloud.dart';

/// Anonymous, aggregate-only usage telemetry. Reports that a transfer happened
/// (a count + byte total + platform bucket) so BIShare's public stats reflect
/// real usage — LAN/nearby transfers never touch the relay otherwise.
///
/// Privacy by design: NO IP, NO file name, NO content — only a byte count and
/// the platform. Opt-out via Settings (default on), fire-and-forget, and every
/// failure is swallowed so it can never affect a transfer.
class TelemetryService {
  TelemetryService(this._prefs);

  final SharedPreferences _prefs;
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: CloudConfig.apiBase,
      connectTimeout: const Duration(seconds: 4),
      sendTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 4),
    ),
  );

  /// Shared SharedPreferences key — the Settings toggle writes it, we read it.
  static const prefKey = 'telemetryEnabled';

  /// Default: on for store builds, opt-in (off) for the FOSS/F-Droid build —
  /// F-Droid policy treats default-on telemetry as a Tracking anti-feature.
  bool get enabled => _prefs.getBool(prefKey) ?? !kFossBuild;

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  /// Fire-and-forget; call once per successful transfer (SENDER side).
  /// [transport] is 'lan' (TCP) or 'quic'.
  void recordTransfer({required int bytes, String transport = 'lan'}) {
    if (!enabled || bytes <= 0) return;
    unawaited(_post(kind: 'send', bytes: bytes, transport: transport));
  }

  /// Fire-and-forget; call once per file successfully RECEIVED over LAN. Counts
  /// as a "download" the relay never sees. [transport] is 'lan' or 'quic'.
  void recordReceive({required int bytes, String transport = 'lan'}) {
    if (!enabled || bytes <= 0) return;
    unawaited(_post(kind: 'receive', bytes: bytes, transport: transport));
  }

  /// Fire-and-forget; call once when a LOCAL (Bonjour/LAN) room is hosted.
  /// No bytes — just a count so local rooms show up in the public stats.
  void recordLocalRoom() {
    if (!enabled) return;
    unawaited(_post(kind: 'room', bytes: 0, transport: 'lan'));
  }

  Future<void> _post({
    required String kind,
    required int bytes,
    required String transport,
  }) async {
    try {
      await _dio.post<void>(
        '/api/v1/telemetry/transfer',
        data: {
          'kind': kind,
          'bytes': bytes,
          'platform': _platform,
          'transport': transport,
        },
      );
    } catch (_) {
      // best-effort — never surfaced to the user
    }
  }
}
