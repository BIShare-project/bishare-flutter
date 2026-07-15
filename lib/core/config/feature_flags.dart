import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/cloud.dart';

/// Remote feature flags from `GET /api/v1/config` (`data.flags`, managed live
/// from the admin panel's Feature Flags page). Cached in prefs so a cold
/// offline launch keeps the last-known state; refreshed once per app run.
///
/// Defaults are the SAFE state when a flag is absent/unreachable:
/// * [driveEnabled] false — the Drive surface stays hidden until launch.
/// * [cloudSyncFree] false — the Pro gate applies unless the flag lifts it.
/// * [loginEnabled] false — sign-in entry points stay hidden until launch.
class FeatureFlags extends ChangeNotifier {
  FeatureFlags(this._prefs);

  static const _cacheKey = 'featureFlagsCache';

  final SharedPreferences _prefs;
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: CloudConfig.apiBase,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  Map<String, dynamic> _flags = const {};

  bool _boolFlag(String key, {required bool orElse}) {
    final v = _flags[key];
    return v is bool ? v : orElse;
  }

  /// Drive (cloud storage UI) visibility — pre-launch it stays hidden.
  bool get driveEnabled => _boolFlag('drive_enabled', orElse: false);

  /// Folder-sync cloud fallback free-for-everyone (pre-IAP period). When false
  /// the Pro tier gate applies.
  bool get cloudSyncFree => _boolFlag('cloud_sync_free', orElse: false);

  /// Sign-in surfaces (Settings row, Drive CTA). Hidden pre-launch — the
  /// magic-link mailer isn't live yet; existing sessions are unaffected.
  bool get loginEnabled => _boolFlag('login_enabled', orElse: false);

  /// Load cached flags synchronously-ish, then refresh from the network in the
  /// background (callers listen for changes).
  Future<void> load() async {
    final raw = _prefs.getString(_cacheKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _flags = (jsonDecode(raw) as Map<String, dynamic>?) ?? const {};
      } on Object {
        _flags = const {};
      }
    }
    unawaited(refresh());
  }

  /// Fetch the live flags; silent on failure (cache/defaults hold).
  Future<void> refresh() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(CloudConfig.config);
      final data = res.data?['data'];
      final flags = data is Map<String, dynamic> ? data['flags'] : null;
      if (flags is Map<String, dynamic>) {
        _flags = flags;
        await _prefs.setString(_cacheKey, jsonEncode(flags));
        notifyListeners();
      }
    } on Object {
      // Offline — last-known cache (or safe defaults) stay in force.
    }
  }
}
