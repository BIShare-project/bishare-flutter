import 'dart:async';

import 'package:flutter/services.dart';

/// Native share-target bridge for Android — replaces the receive_sharing_intent
/// plugin. When another app shares files into BIShare, the native side copies
/// them to cache and hands us the local paths over a MethodChannel; the shell
/// drops them into the compose tray.
///
/// iOS does NOT use this: there, a self-contained native Share Extension does
/// the whole transfer inside the share sheet, so the app is never involved.
class ShareIntentService {
  ShareIntentService() {
    _channel.setMethodCallHandler(_handle);
  }

  static const _channel = MethodChannel('app.bishare/share');
  final _controller = StreamController<List<String>>.broadcast();

  /// File paths shared while the app is already running (warm start).
  Stream<List<String>> get onShare => _controller.stream;

  Future<void> _handle(MethodCall call) async {
    if (call.method == 'onShare') {
      final paths = (call.arguments as List?)?.cast<String>() ?? const [];
      if (paths.isNotEmpty) _controller.add(paths);
    }
  }

  /// File paths that launched the app from a cold start (drained once).
  Future<List<String>> getInitial() async {
    try {
      final res = await _channel.invokeMethod<List<Object?>>('getInitialShare');
      return res?.cast<String>() ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  void dispose() => _controller.close();
}
