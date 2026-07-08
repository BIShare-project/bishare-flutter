import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';

/// Generates a small base64 JPEG thumbnail (max ~120px) for an image or video,
/// matching the native room thumbnail so peers see previews in the file list.
/// Returns null for unsupported types or on any failure (best-effort).
Future<String?> generateRoomThumbnail(String path, String mime) async {
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
