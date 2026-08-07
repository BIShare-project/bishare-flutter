import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this device is an Android TV / Leanback device. Resolved once at
/// startup (see `main()`), then read synchronously by the router to pick the
/// TV shell over the touch shell. Defaults to false everywhere else.
bool isTvDevice = false;

/// Native bridge to ask Android whether we're on a TV (Leanback). No-op that
/// resolves to false off Android — the touch UI is always the safe default.
class DeviceChannel {
  const DeviceChannel._();

  static const MethodChannel _channel = MethodChannel('app.bishare/device');

  static Future<bool> isTv() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isTv');
      return result ?? false;
    } on Object catch (e) {
      debugPrint('[DeviceChannel] isTv failed: $e');
      return false;
    }
  }
}
