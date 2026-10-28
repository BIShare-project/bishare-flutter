import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../core/ui/app_ui.dart';
import '../../send/data/send_media_library.dart';

/// Press and hold a photo or video in the Send grid to look at it bigger;
/// lifting the finger closes it (the peek never selects). A video plays
/// muted. Shown in the root overlay, above the tabs and the selection bar.
class AssetPeek {
  AssetPeek._(this._entry);

  final OverlayEntry _entry;
  bool _closed = false;

  static AssetPeek show(BuildContext context, AssetEntity asset, int thumbPx) {
    final entry = OverlayEntry(
      builder: (_) => _PeekView(asset: asset, thumbPx: thumbPx),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return AssetPeek._(entry);
  }

  /// Safe before the entry's first frame too: `mounted` is still false
  /// then, but the entry is already in the overlay and must leave.
  void close() {
    if (_closed) return;
    _closed = true;
    _entry.remove();
  }
}

class _PeekView extends StatefulWidget {
  const _PeekView({required this.asset, required this.thumbPx});

  final AssetEntity asset;

  /// The grid tile's size, already in the image cache: shown at once.
  final int thumbPx;

  @override
  State<_PeekView> createState() => _PeekViewState();
}

class _PeekViewState extends State<_PeekView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: AppMotion.select,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _in,
    curve: AppMotion.enter,
  );
  Uint8List? _large;
  VideoPlayerController? _video;

  bool get _isVideo => widget.asset.type == AssetType.video;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLarge());
    if (_isVideo) unawaited(_loadVideo());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_in.isDismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _in.value = 1;
      } else {
        unawaited(_in.forward());
      }
    }
  }

  Future<void> _loadLarge() async {
    final a = widget.asset;
    // About screen size, the asset's own proportions.
    const edge = 1080;
    final w = a.width, h = a.height;
    final size = w <= 0 || h <= 0
        ? const ThumbnailSize.square(edge)
        : w >= h
        ? ThumbnailSize(edge, (edge * h / w).round())
        : ThumbnailSize((edge * w / h).round(), edge);
    final bytes = await a.thumbnailDataWithSize(size, quality: 88);
    if (mounted && bytes != null) setState(() => _large = bytes);
  }

  Future<void> _loadVideo() async {
    final file = await widget.asset.file;
    if (file == null || !mounted) return;
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
    } on Object {
      await c.dispose();
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _video = c);
  }

  @override
  void dispose() {
    _in.dispose();
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.asset;
    final ratio = a.width > 0 && a.height > 0 ? a.width / a.height : 1.0;
    final video = _video;
    final Widget picture = video != null && video.value.isInitialized
        ? VideoPlayer(video)
        : _large != null
        ? Image.memory(_large!, fit: BoxFit.cover, gaplessPlayback: true)
        : Image(
            image: AssetThumbProvider(a, px: widget.thumbPx),
            fit: BoxFit.cover,
          );
    // Nothing here takes a touch: the finger that opened the peek still
    // belongs to the grid, which closes it on release.
    return IgnorePointer(
      child: FadeTransition(
        opacity: _curve,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.72),
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(_curve),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: video?.value.isInitialized ?? false
                        ? video!.value.aspectRatio
                        : ratio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: picture,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
