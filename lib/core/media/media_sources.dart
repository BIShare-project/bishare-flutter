import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Off-UI-isolate media helpers used by the staging tray: zip a folder, stage a
/// text note, and re-encode images to a smaller JPEG.
class MediaSources {
  MediaSources._();

  static const _uuid = Uuid();

  /// Zips [dirPath] into a temp `<folder>.zip` and returns its path. On failure
  /// the half-written archive is closed + deleted (no leaked fd / orphan file).
  static Future<String> zipDirectory(String dirPath) async {
    final tmp = await getTemporaryDirectory();
    final name = p.basename(dirPath);
    final zipPath = p.join(tmp.path, '$name-${_uuid.v4().substring(0, 8)}.zip');
    final encoder = ZipFileEncoder()..create(zipPath);
    try {
      await encoder.addDirectory(Directory(dirPath), includeDirName: true);
    } on Object {
      await encoder.close();
      final f = File(zipPath);
      if (f.existsSync()) f.deleteSync();
      rethrow;
    }
    await encoder.close();
    return zipPath;
  }

  /// Writes [text] to a temp `.txt` and returns its path. The filename always
  /// carries a unique suffix so repeated pastes/notes stage as distinct files.
  static Future<String> writeText(String text, {String? name}) async {
    final tmp = await getTemporaryDirectory();
    final base = (name != null && name.trim().isNotEmpty)
        ? _safe(name.trim())
        : 'note';
    final file = File(
      p.join(tmp.path, '$base-${_uuid.v4().substring(0, 8)}.txt'),
    );
    await file.writeAsString(text);
    return file.path;
  }

  /// Writes a vCard string to a temp `.vcf` and returns its path.
  static Future<String> writeVcf(String vcard, {String? name}) async {
    final tmp = await getTemporaryDirectory();
    final base = (name != null && name.trim().isNotEmpty)
        ? _safe(name.trim())
        : 'contact-${_uuid.v4().substring(0, 8)}';
    final file = File(p.join(tmp.path, '$base.vcf'));
    await file.writeAsString(vcard);
    return file.path;
  }

  /// Copies an installed app's APK to a temp `<App>_<version>.apk` and returns
  /// its path. The tray then holds a stable copy with a receiver-friendly name
  /// (not `/data/app/…/base.apk`, which changes on update and reads as noise).
  static Future<String> stageApk(
    String apkPath, {
    required String appName,
    required String version,
  }) async {
    final tmp = await getTemporaryDirectory();
    final base = _safe(appName).replaceAll(' ', '_');
    // Keep dots in versions ("2.24.1"), unlike [_safe].
    final ver = version.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final name = [
      if (base.isNotEmpty) base else 'app',
      if (ver.isNotEmpty) ver,
    ].join('_');
    final out = p.join(tmp.path, '$name.apk');
    await File(apkPath).copy(out);
    return out;
  }

  /// Re-encodes the image at [path] to JPEG capped at [maxDimension] px (long
  /// edge) and [quality]. Returns a temp path, or the original path when the
  /// file isn't a decodable raster image or [maxDimension] is 0.
  static Future<String> compressImage(
    String path, {
    required int maxDimension,
    required int quality,
  }) async {
    if (quality >= 100 && maxDimension == 0) return path;
    try {
      final bytes = await File(path).readAsBytes();
      final out = await compute(_encodeJob, (
        bytes: bytes,
        maxDim: maxDimension,
        quality: quality,
      ));
      if (out == null) return path;
      final tmp = await getTemporaryDirectory();
      final file = File(
        p.join(tmp.path, 'img-${_uuid.v4().substring(0, 8)}.jpg'),
      );
      await file.writeAsBytes(out);
      return file.path;
    } on Object {
      return path;
    }
  }

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^\w\- ]'), '_').trim();
}

/// Top-level so it can run in a background isolate via [compute].
Uint8List? _encodeJob(({Uint8List bytes, int maxDim, int quality}) job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  var image = decoded;
  final longEdge = image.width > image.height ? image.width : image.height;
  if (job.maxDim > 0 && longEdge > job.maxDim) {
    image = image.width >= image.height
        ? img.copyResize(image, width: job.maxDim)
        : img.copyResize(image, height: job.maxDim);
  }
  return img.encodeJpg(image, quality: job.quality);
}
