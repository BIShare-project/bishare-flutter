import 'dart:io';

import 'package:flutter/services.dart';

/// A launcher app installed on this device, shareable as its APK file.
class InstalledApp {
  const InstalledApp({
    required this.name,
    required this.packageName,
    required this.version,
    required this.apkPath,
    required this.sizeBytes,
    required this.splitCount,
    this.splitPaths = const [],
    this.icon,
  });

  final String name;
  final String packageName;
  final String version;

  /// The installed base APK (`ApplicationInfo.sourceDir`).
  final String apkPath;

  /// Size of what actually gets sent: the base APK plus every split.
  final int sizeBytes;

  /// Number of split APKs beside the base (App Bundle installs).
  final int splitCount;

  /// The installed split APKs (`ApplicationInfo.splitSourceDirs`): the ABI,
  /// density and language parts of an App Bundle install. Empty for an app
  /// installed as a single APK.
  final List<String> splitPaths;

  /// Launcher icon rasterized to a small PNG, or null if it couldn't render.
  final Uint8List? icon;

  /// Installed as split APKs. Such an app is sent as one `.apks` archive (base
  /// + splits): the base alone is marked `isSplitRequired` and cannot install.
  bool get isSplit => splitPaths.isNotEmpty;
}

/// "App Share" (SHAREit-style): lists launcher apps so their APKs can be
/// staged in the send tray. Android-only — other platforms don't expose
/// installed app binaries.
///
/// Package visibility comes from the MAIN/LAUNCHER `<queries>` entry in the
/// manifest, NOT the Play-restricted QUERY_ALL_PACKAGES permission — so the
/// list is exactly the apps with a launcher icon.
class InstalledAppsChannel {
  const InstalledAppsChannel._();

  static const _channel = MethodChannel('app.bishare/apps');

  /// Whether installed apps can be listed on this platform.
  static bool get isSupported => Platform.isAndroid;

  /// All launcher apps (excluding BIShare itself), sorted by name. Empty on
  /// unsupported platforms or any native failure — listing is best-effort.
  static Future<List<InstalledApp>> list() async {
    if (!isSupported) return const [];
    try {
      final raw = await _channel.invokeListMethod<Object?>('list');
      if (raw == null) return const [];
      return raw.whereType<Map<Object?, Object?>>().map((m) {
        return InstalledApp(
          name: m['name'] as String? ?? '',
          packageName: m['package'] as String? ?? '',
          version: m['version'] as String? ?? '',
          apkPath: m['apkPath'] as String? ?? '',
          sizeBytes: m['sizeBytes'] as int? ?? 0,
          splitCount: m['splitCount'] as int? ?? 0,
          splitPaths:
              (m['splitPaths'] as List<Object?>?)
                  ?.whereType<String>()
                  .toList() ??
              const [],
          icon: m['icon'] as Uint8List?,
        );
      }).toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}
