import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

  /// Last UTC date (`YYYY-MM-DD`) this install reported itself active.
  static const _activeDayKey = 'telemetryActiveDay';

  /// When (ms since epoch) this install last sent the thirty-day flag.
  static const _activeMonthKey = 'telemetryActiveMonthAt';

  static const _monthWindow = Duration(days: 30);

  /// Which flags an active ping should carry, from what was sent before.
  ///
  /// `day` is true on the first launch of a UTC calendar day; `month` is true
  /// when thirty days have passed since it was last sent (or it never was).
  /// Because an install sends `month` at most once per thirty days, the server
  /// can add the flags up over any thirty-day window and get the number of
  /// installs opened in it — without a device ever naming itself. A clock set
  /// backwards reads as "not due yet" rather than as a second ping.
  @visibleForTesting
  static ({bool day, bool month}) activeFlags({
    required String? lastDay,
    required int? lastMonthAtMs,
    required DateTime now,
  }) {
    final today = _utcDay(now);
    final sinceMonth = lastMonthAtMs == null
        ? null
        : now.toUtc().millisecondsSinceEpoch - lastMonthAtMs;
    return (
      day: lastDay != today,
      month: sinceMonth == null || sinceMonth >= _monthWindow.inMilliseconds,
    );
  }

  static String _utcDay(DateTime t) => t.toUtc().toIso8601String().substring(0, 10);

  /// Fire-and-forget; call once per app launch. Reports that this install was
  /// opened — a count and the platform, nothing that identifies the device.
  /// What was sent is remembered only after the server accepts it, so a launch
  /// with no network is simply reported by the next one.
  void recordActive() {
    if (!enabled) return;
    unawaited(_postActive(DateTime.now()));
  }

  Future<void> _postActive(DateTime now) async {
    final flags = activeFlags(
      lastDay: _prefs.getString(_activeDayKey),
      lastMonthAtMs: _prefs.getInt(_activeMonthKey),
      now: now,
    );
    if (!flags.day && !flags.month) return;
    try {
      await _dio.post<void>(
        '/api/v1/telemetry/active',
        data: {'platform': _platform, 'day': flags.day, 'month': flags.month},
      );
      if (flags.day) await _prefs.setString(_activeDayKey, _utcDay(now));
      if (flags.month) {
        await _prefs.setInt(_activeMonthKey, now.toUtc().millisecondsSinceEpoch);
      }
    } catch (_) {
      // best-effort — the next launch reports instead
    }
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
