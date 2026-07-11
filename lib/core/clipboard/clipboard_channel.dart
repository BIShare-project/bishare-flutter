import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// An image read off the system clipboard: encoded [bytes] plus their [mime].
class ClipboardImageData {
  const ClipboardImageData({required this.bytes, required this.mime});

  final Uint8List bytes;
  final String mime;
}

/// Platform channel for IMAGE clipboard access — Flutter's own [Clipboard]
/// API is text-only. Backed by `app.bishare/clipboard` handlers registered
/// where each platform's existing channels live (macOS `MainFlutterWindow`,
/// iOS `AppDelegate`, Android `MainActivity`).
///
/// Methods:
/// - `getImage()` → `{bytes, mime}?` — the current clipboard image (PNG on
///   Apple platforms; original encoded bytes on Android), or null.
/// - `setImage(bytes, mime)` → bool — place an image on the clipboard.
/// - `changeCount()` → int — a cheap monotonic pasteboard generation counter
///   (NSPasteboard/UIPasteboard changeCount; a primary-clip-changed counter on
///   Android) so the poll loop can skip expensive image reads when nothing was
///   copied since the last poll.
///
/// Windows/Linux have no native handler yet (best-effort per plan §1: the
/// runners can't be compile-verified from this host) — [isSupported] is false
/// there and every call degrades to null/false, exactly as it would on a
/// `notImplemented` reply.
class ClipboardImageChannel {
  ClipboardImageChannel._();

  static const MethodChannel _channel = MethodChannel('app.bishare/clipboard');

  /// Whether this platform has a native image-clipboard handler.
  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isIOS || Platform.isAndroid);

  /// The current clipboard image, or null when the clipboard holds none (or
  /// the platform is unsupported). Best-effort: channel errors read as null.
  static Future<ClipboardImageData?> getImage() async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getImage',
      );
      final bytes = res?['bytes'];
      if (bytes is! Uint8List || bytes.isEmpty) return null;
      final mime = res?['mime'];
      return ClipboardImageData(
        bytes: bytes,
        mime: mime is String && mime.isNotEmpty ? mime : 'image/png',
      );
    } on Object {
      return null; // MissingPluginException / PlatformException → unsupported
    }
  }

  /// Put [bytes] (an encoded image of type [mime]) on the system clipboard.
  static Future<bool> setImage(Uint8List bytes, String mime) async {
    if (!isSupported || bytes.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setImage', {
        'bytes': bytes,
        'mime': mime,
      });
      return ok ?? false;
    } on Object {
      return false;
    }
  }

  /// A cheap pasteboard generation counter — bumps whenever ANYTHING is copied
  /// (text included). Null when unavailable; callers then fall back to reading
  /// the image every poll.
  static Future<int?> changeCount() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<int>('changeCount');
    } on Object {
      return null;
    }
  }
}
