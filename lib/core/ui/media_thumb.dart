import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'app_format.dart';
import 'app_svg_icon.dart';

/// A rounded thumbnail tile for a file: an image preview for photos, a generated
/// frame for videos (mobile only, cached), or a tinted file-type icon otherwise.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.path,
    required this.mime,
    this.size = 38,
    this.radius = 11,
  });

  final String? path;
  final String? mime;
  final double size;
  final double radius;

  /// video_thumbnail is Android/iOS-only.
  static bool get _videoSupported => Platform.isIOS || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final m = mime ?? '';
    final hasFile = path != null && File(path!).existsSync();

    if (hasFile && m.startsWith('image/')) {
      return _clip(
        Image.file(
          File(path!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 2.6).round(),
          errorBuilder: (_, _, _) => _iconTile(cs, m),
        ),
      );
    }
    if (hasFile && m.startsWith('video/') && _videoSupported) {
      return _clip(
        _VideoThumb(path: path!, size: size, fallback: _iconTile(cs, m)),
      );
    }
    return _iconTile(cs, m);
  }

  Widget _clip(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(width: size, height: size, child: child),
  );

  Widget _iconTile(ShadColorScheme cs, String m) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.muted,
      borderRadius: BorderRadius.circular(radius),
    ),
    child: AppSvgIcon(fileIcon(m), size: size * 0.5, color: cs.mutedForeground),
  );
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({
    required this.path,
    required this.size,
    required this.fallback,
  });

  final String path;
  final double size;
  final Widget fallback;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  // Process-lifetime cache so a row rebuild doesn't regenerate the frame.
  static final Map<String, Uint8List?> _cache = {};

  Uint8List? _data;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_cache.containsKey(widget.path)) {
      setState(() {
        _data = _cache[widget.path];
        _done = true;
      });
      return;
    }
    Uint8List? d;
    try {
      d = await VideoThumbnail.thumbnailData(
        video: widget.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: (widget.size * 3).round(),
        quality: 60,
      );
    } on Object {
      d = null;
    }
    _cache[widget.path] = d;
    if (mounted) {
      setState(() {
        _data = d;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) return const ColoredBox(color: Colors.black12);
    if (_data == null) return widget.fallback;
    return Image.memory(
      _data!,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
    );
  }
}
