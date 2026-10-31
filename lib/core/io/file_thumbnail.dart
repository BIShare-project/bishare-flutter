import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';

/// Generates a small base64 JPEG thumbnail (max ~120px) for an image or video:
/// the preview a room member sees in the file list, and the one a nearby
/// device sees in the offer before accepting. Returns null for unsupported
/// types or on any failure (best-effort).
Future<String?> generateThumbnail(String path, String mime) async {
  try {
    if (mime.startsWith('image/')) {
      Uint8List? jpg;
      if (Platform.isIOS || Platform.isAndroid) {
        // Native decoder — handles HEIC (the iPhone default) that the pure-Dart
        // `image` package cannot decode, plus resize + JPEG encode in one pass.
        jpg = await FlutterImageCompress.compressWithFile(
          path,
          minWidth: 120,
          minHeight: 120,
          quality: 70,
          format: CompressFormat.jpeg,
        );
      } else {
        // Desktop: pure-Dart resize (JPEG/PNG; desktop photos aren't HEIC).
        final bytes = await File(path).readAsBytes();
        jpg = await compute(_resizeToJpg, bytes);
      }
      return jpg == null ? null : base64Encode(jpg);
    }
    if (mime.startsWith('video/') && (Platform.isIOS || Platform.isAndroid)) {
      final data = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 120,
        quality: 70,
      );
      return data == null ? null : base64Encode(data);
    }
  } on Object {
    // best-effort — no thumbnail
  }
  return null;
}

/// Runs on a background isolate (decode can be heavy for large photos).
Uint8List? _resizeToJpg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: 120)
      : img.copyResize(decoded, height: 120);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
}

/// A Cloud room carries the preview in a header (sealed into X-Enc-Meta in an
/// encrypted room, where the server takes at most 12,000 characters, else a
/// plain upload is refused with ROOM_ENCRYPTION_REQUIRED). A preview of
/// [maxChars] or more is made again at the web client's size (longest side
/// 96 px, quality 60); one still too big is left out, the file goes anyway.
Future<String?> fitRoomThumbnail(String? base64Jpg, {int maxChars = 6000}) async {
  if (base64Jpg == null || base64Jpg.length < maxChars) return base64Jpg;
  try {
    final small = await compute(_shrinkJpg, base64Decode(base64Jpg));
    if (small == null) return null;
    final out = base64Encode(small);
    return out.length < maxChars ? out : null;
  } on Object {
    return null;
  }
}

Uint8List? _shrinkJpg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final resized = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: 96)
      : img.copyResize(decoded, height: 96);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 60));
}
