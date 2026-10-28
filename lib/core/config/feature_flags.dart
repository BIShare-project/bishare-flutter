import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/cloud.dart';

/// Remote feature flags from `GET /api/v1/config` (`data.flags`, managed live
/// from the admin panel's Feature Flags page). Cached in prefs so a cold
/// offline launch keeps the last-known state; refreshed once per app run.
class FeatureFlags extends ChangeNotifier {
  FeatureFlags(this._prefs);

  static const _cacheKey = 'featureFlagsCache';
  static const _vaultTesterKey = 'vaultTester';

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

  /// Folder-sync cloud fallback free-for-everyone (pre-IAP period). When false
  /// the Pro tier gate applies.
  bool get cloudSyncFree => _boolFlag('cloud_sync_free', orElse: false);

  /// The one-time question about a paid storage product (the card in
  /// `features/home/widgets/drive_interest_card.dart`). Off unless an admin
  /// turns `drive_interest_enabled` on.
  bool get driveInterestEnabled =>
      _boolFlag('drive_interest_enabled', orElse: false);

  /// The app↔web Nearby bridge (app appears in the browser Nearby tab on the
  /// same network, and vice versa). ON by default in code — the remote flag is
  /// purely a kill-switch (set `app_web_nearby_enabled=false` in admin Flags
  /// to disable remotely); no flag row is required for the feature to work.
  bool get webNearbyEnabled =>
      _boolFlag('app_web_nearby_enabled', orElse: true);

  /// The in-app photo and video grid of the Send tab on Android
  /// (redesign-plan.md D3). On by default (owner 2026-10-28): READ_MEDIA_*
  /// is already granted for Drive backup, and the Play declaration gains
  /// sending as a second use before the release. An admin can still turn
  /// `send_gallery_android` off, which brings back the system picker.
  bool get sendGalleryAndroid =>
      _boolFlag('send_gallery_android', orElse: true);

  /// BIShare Drive (code name "vault"). The server flag `vault_enabled` is
  /// `true` (open to everyone), `"internal"` (testers on the server's
  /// allowlist) or absent/false. Anything else counts as off.
  bool get vaultOpen => _flags['vault_enabled'] == true;
  bool get vaultInternal => _flags['vault_enabled'] == 'internal';

  /// A tester's own switch on this device. While the flag is "internal" it is
  /// what shows the Drive entry; the server still refuses sign-ins that are
  /// not on its allowlist.
  bool get vaultTester => _prefs.getBool(_vaultTesterKey) ?? false;

  Future<void> setVaultTester(bool on) async {
    await _prefs.setBool(_vaultTesterKey, on);
    notifyListeners();
  }

  /// Whether any Drive entry point is shown. Hidden unless the flag is on, or
  /// "internal" on a tester's device (drive-plan.md task 3.1).
  bool get vaultVisible => vaultOpen || (vaultInternal && vaultTester);

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
