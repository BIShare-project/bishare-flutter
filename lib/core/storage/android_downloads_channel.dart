import 'dart:io';
import 'package:flutter/services.dart';

/// Android-only: get the public Downloads directory path.
///
/// On Android 10+ (scoped storage), Downloads is always writable and
/// doesn't require any permissions. Returns the path like
/// `/storage/emulated/0/Download`.
class AndroidDownloadsPath {
  AndroidDownloadsPath._();

  static const _channel = MethodChannel('app.bishare/android_downloads');

  static bool get isSupported => Platform.isAndroid;

  /// Get the public Downloads directory path on Android.
  /// Returns null on other platforms or if the platform channel is unavailable.
  static Future<String?> getPublicDownloads() async {
    if (!Platform.isAndroid) return null;
    try {
      final path = await _channel.invokeMethod<String>('getPublicDownloads');
      return (path != null && path.isNotEmpty) ? path : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
