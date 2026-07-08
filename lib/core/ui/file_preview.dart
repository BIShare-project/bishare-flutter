import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'app_format.dart';
import 'app_sheet.dart';
import 'app_svg_icon.dart';

/// Opens a rich preview of a local [path]. Images get a full-screen pinch-zoom
/// viewer, videos a poster frame with a play affordance (opens in the system
/// player), and every other type a premium glass card with Open + Share.
///
/// Reusable across the compose tray, inbox, history and file manager — anywhere
/// a file row is tapped.
Future<void> showFilePreview(
  BuildContext context, {
  required String path,
  required String name,
  required String mimeType,
  int? size,
}) {
  final isImage = mimeType.startsWith('image/');
  final isVideo = mimeType.startsWith('video/');
  final exists = File(path).existsSync();

  if (exists && (isImage || isVideo)) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) =>
            _MediaPreviewPage(path: path, name: name, isVideo: isVideo),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // Documents / archives / anything else → glass hero card.
  return showGlassModal<void>(
    context,
    builder: (ctx) => _FileInfoCard(
      path: path,
      name: name,
      mimeType: mimeType,
      size: size,
    ),
  );
}

Future<void> _open(BuildContext context, String path) async {
  final res = await OpenFilex.open(path);
  if (res.type != ResultType.done && context.mounted) {
    toast(context, 'common.no_app_open'.tr(), type: ToastType.error);
  }
}

void _share(String path) =>
    SharePlus.instance.share(ShareParams(files: [XFile(path)]));

// ---------------------------------------------------------------------------
// Full-screen image / video viewer
// ---------------------------------------------------------------------------

class _MediaPreviewPage extends StatelessWidget {
  const _MediaPreviewPage({
    required this.path,
    required this.name,
    required this.isVideo,
  });

  final String path;
  final String name;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: isVideo
                ? _VideoPoster(path: path)
                : PhotoView(
                    imageProvider: FileImage(File(path)),
                    backgroundDecoration: const BoxDecoration(
                      color: Colors.black,
                    ),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3,
                    initialScale: PhotoViewComputedScale.contained,
                    loadingBuilder: (_, _) =>
                        const Center(child: CircularProgressIndicator()),
                    errorBuilder: (_, _, _) => const Center(
                      child: AppSvgIcon(
                        AppIcons.imageOff,
                        size: 48,
                        color: Colors.white54,
                      ),
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  _RoundButton(
                    icon: AppIcons.close,
                    onTap: () {
                      tapHaptic();
                      Navigator.pop(context);
                    },
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _RoundButton(
                    icon: AppIcons.shareLink,
                    onTap: () {
                      tapHaptic();
                      _share(path);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A circular, semi-transparent overlay button for the media viewer's top bar.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: AppSvgIcon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

/// A video poster frame (mobile) with a large play button that opens the file
/// in the system player. On desktop (no thumbnailer) it's a dark placeholder.
class _VideoPoster extends StatefulWidget {
  const _VideoPoster({required this.path});

  final String path;

  static bool get _supported => Platform.isIOS || Platform.isAndroid;

  @override
  State<_VideoPoster> createState() => _VideoPosterState();
}

class _VideoPosterState extends State<_VideoPoster> {
  Uint8List? _frame;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_VideoPoster._supported) {
      setState(() => _done = true);
      return;
    }
    Uint8List? d;
    try {
      d = await VideoThumbnail.thumbnailData(
        video: widget.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 1080,
        quality: 75,
      );
    } on Object {
      d = null;
    }
    if (mounted) {
      setState(() {
        _frame = d;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        tapHaptic();
        _open(context, widget.path);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_frame != null)
            Image.memory(_frame!, fit: BoxFit.contain)
          else
            const ColoredBox(color: Color(0xFF0A0A0A)),
          if (_done)
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 2),
                ),
                child: const AppSvgIcon(
                  AppIcons.play,
                  size: 34,
                  color: Colors.white,
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: 40),
              child: Text(
                'Tap to play',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass hero card for documents / archives / other types
// ---------------------------------------------------------------------------

class _FileInfoCard extends StatelessWidget {
  const _FileInfoCard({
    required this.path,
    required this.name,
    required this.mimeType,
    this.size,
  });

  final String path;
  final String name;
  final String mimeType;
  final int? size;

  String get _typeLabel {
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : '';
    if (ext.isNotEmpty && ext.length <= 5) return ext;
    final slash = mimeType.indexOf('/');
    return slash >= 0
        ? mimeType.substring(slash + 1).toUpperCase()
        : 'FILE';
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
              ),
              child: AppSvgIcon(fileIcon(mimeType), size: 40, color: cs.primary),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [_typeLabel, if (size != null) formatBytes(size!)].join('  ·  '),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          const SizedBox(height: 22),
          ShadButton(
            size: ShadButtonSize.lg,
            leading: const AppSvgIcon(AppIcons.externalLink, size: 18),
            onPressed: () {
              tapHaptic();
              _open(context, path);
            },
            child: Text('common.open'.tr()),
          ),
          const SizedBox(height: 10),
          ShadButton.outline(
            size: ShadButtonSize.lg,
            leading: const AppSvgIcon(AppIcons.shareLink, size: 18),
            onPressed: () {
              tapHaptic();
              _share(path);
            },
            child: Text('common.share'.tr()),
          ),
        ],
      ),
    );
  }
}
