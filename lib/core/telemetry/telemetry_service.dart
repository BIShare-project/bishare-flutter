import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

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

  bool get enabled => _prefs.getBool(prefKey) ?? true;

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  /// Fire-and-forget; call once per successful transfer (sender side).
  /// [transport] is 'lan' (TCP) or 'quic'.
  void recordTransfer({required int bytes, String transport = 'lan'}) {
    if (!enabled || bytes <= 0) return;
    unawaited(_post(bytes, transport));
  }

  Future<void> _post(int bytes, String transport) async {
    try {
      await _dio.post<void>(
        '/api/v1/telemetry/transfer',
        data: {'bytes': bytes, 'platform': _platform, 'transport': transport},
      );
    } catch (_) {
      // best-effort — never surfaced to the user
    }
  }
}
