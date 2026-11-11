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
    this.liveGroup,
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

  /// Shared by the still and the motion of one Live Photo
  /// ([FileMetadata.liveGroup]).
  final String? liveGroup;

  File get file => File(path);

  /// The same file sent under [newName] (the photo library's own name for an
  /// exported original, not the export's file name).
  SendableFile withName(String newName) => SendableFile(
    id: id,
    path: path,
    name: newName,
    size: size,
    mimeType: lookupMimeType(newName) ?? mimeType,
    mtimeMs: mtimeMs,
    liveGroup: liveGroup,
  );

  /// The same file as one half of the Live Photo [group].
  SendableFile inLiveGroup(String group) => SendableFile(
    id: id,
    path: path,
    name: name,
    size: size,
    mimeType: mimeType,
    mtimeMs: mtimeMs,
    liveGroup: group,
  );
}
