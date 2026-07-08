import 'dart:io';

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
    );
  }

  final String id;
  final String path;
  final String name;
  final int size;
  final String mimeType;

  File get file => File(path);
}
