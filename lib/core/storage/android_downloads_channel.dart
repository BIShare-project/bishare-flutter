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

  /// Modification time (Unix ms) of the original file behind a picked content
  /// [uri], or null when the provider does not say. See `lastModifiedOf` in
  /// MainActivity.kt.
  static Future<int?> lastModifiedOf(String uri) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('lastModifiedOf', {'uri': uri});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Puts received files into MediaStore (or takes deleted ones out), so the
  /// gallery shows them where they were saved. Returns how many are indexed;
  /// 0 on other platforms or when the channel fails.
  static Future<int> scanMedia(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) return 0;
    try {
      return await _channel.invokeMethod<int>('scanMedia', {'paths': paths}) ??
          0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }
}
