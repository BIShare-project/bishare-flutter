import 'dart:io';

import 'package:bishare/core/io/preserve_mtime.dart';
import 'package:mime/mime.dart';

/// A local file queued to send. Byte content is streamed from [path] — never
/// buffered whole (matches the native "stream everything" rule).
class SendableFile {
  const SendableFile({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
    this.mtimeMs,
  });

  /// Builds a [SendableFile] from a filesystem path.
  static SendableFile fromPath(String path, {required String id}) {
    final file = File(path);
    final name = path.split(Platform.pathSeparator).last;
    return SendableFile(
      id: id,
      path: path,
      name: name,
      size: file.lengthSync(),
      mimeType: lookupMimeType(name) ?? 'application/octet-stream',
      mtimeMs: mtimeOf(file),
    );
  }

  final String id;
  final String path;
  final String name;
  final int size;
  final String mimeType;

  /// Modification time on this device (Unix ms), sent so the receiver can keep
  /// "Date modified". Null when the filesystem has none.
  final int? mtimeMs;

  File get file => File(path);
}
