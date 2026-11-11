import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../io/scratch_dir.dart';

/// A received photo at tile size, for grids of many (Inbox).
///
/// On phones the small JPEG is made by the platform's image library on its
/// own thread, at most two at a time, and kept on disk, so Flutter only ever
/// decodes a few KB. Decoding the originals in Flutter (a 12 MP HEIC each)
/// filled the hardware decoder with 100 received iPhone photos and froze the
/// app ("isn't responding") at start, because the Inbox builds with it.
///
/// Elsewhere it is the file itself, resized while decoding.
ImageProvider fileThumbImage(String path, int px) {
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    return FileThumbProvider(path, px);
  }
  return ResizeImage(
    FileImage(File(path)),
    width: px,
    policy: ResizeImagePolicy.fit,
  );
}

@immutable
class FileThumbProvider extends ImageProvider<FileThumbProvider> {
  const FileThumbProvider(this.path, this.px);

  final String path;

  /// Shortest side of the thumbnail, in physical pixels.
  final int px;

  @override
  Future<FileThumbProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    FileThumbProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load(key, decode));

  static Future<ImageInfo> _load(
    FileThumbProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await _thumbBytes(key.path, key.px);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('no thumbnail for ${key.path}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  static Directory? _dir;
  static int _running = 0;
  static final _waiting = <Completer<void>>[];

  /// The cached JPEG, or a new one made now (two at a time).
  static Future<Uint8List?> _thumbBytes(String path, int px) async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final stamp = file.lastModifiedSync().millisecondsSinceEpoch;
    final name = sha1.convert(utf8.encode('$path|$stamp|$px')).toString();
    final dir = _dir ??= Directory(
      '${(await appTempDir()).path}${Platform.pathSeparator}inbox_thumbs',
    );
    final cached = File('${dir.path}${Platform.pathSeparator}$name.jpg');
    if (cached.existsSync()) return cached.readAsBytes();

    if (_running >= 2) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    try {
      final jpg = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: px,
        minHeight: px,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (jpg == null || jpg.isEmpty) return null;
      try {
        await dir.create(recursive: true);
        await cached.writeAsBytes(jpg, flush: false);
      } on Object {
        // No cache this time; the thumbnail still shows.
      }
      return jpg;
    } on Object {
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FileThumbProvider && other.path == path && other.px == px;

  @override
  int get hashCode => Object.hash(path, px);
}
