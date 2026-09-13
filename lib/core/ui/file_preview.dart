import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:universal_file_viewer/universal_file_viewer.dart' as ufv;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'app_format.dart';
import 'app_sheet.dart';
import 'app_svg_icon.dart';
import 'file_open.dart';

/// Opens a rich preview of a local [path]:
/// - images: full-screen pinch-zoom viewer (every platform);
/// - videos: an in-app player with play/pause and scrubbing;
/// - PDF, Word (.docx), Excel/CSV and Markdown: rendered in-app by
///   universal_file_viewer;
/// - plain text: a scrollable, selectable page;
/// - anything else: a glass card with Open + Share.
///
/// The in-app video and document viewers exist on Android, iOS and macOS only
/// (the platforms universal_file_viewer and video_player support); Windows and
/// Linux keep the poster / card and hand the file to the system app.
///
/// Reusable across the compose tray, inbox, history, file manager and rooms —
/// anywhere a file row is tapped.
Future<void> showFilePreview(
  BuildContext context, {
  required String path,
  required String name,
  required String mimeType,
  int? size,
}) {
  final kind = File(path).existsSync()
      ? _previewKind(path: path, name: name, mimeType: mimeType)
      : null;

  if (kind != null) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) =>
            _PreviewPage(path: path, name: name, kind: kind),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // Everything else → glass hero card.
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

enum _PreviewKind { image, video, videoPoster, document, text }

/// Platforms with an in-app video player and document renderer.
bool get _inAppViewers => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Text files are read whole into memory, so only up to this size.
const _maxTextBytes = 2 * 1024 * 1024;

_PreviewKind? _previewKind({
  required String path,
  required String name,
  required String mimeType,
}) {
  if (mimeType.startsWith('image/')) return _PreviewKind.image;
  if (mimeType.startsWith('video/')) {
    return _inAppViewers ? _PreviewKind.video : _PreviewKind.videoPoster;
  }
  if (!_inAppViewers) return null;

  // universal_file_viewer picks its renderer from the path's extension, so the
  // path (not only the display name) must carry a type it can render.
  final ext = p.extension(name).toLowerCase();
  if (ext == '.txt' || mimeType == 'text/plain') {
    return File(path).lengthSync() <= _maxTextBytes ? _PreviewKind.text : null;
  }
  switch (ufv.detectFileType(path)) {
    case ufv.FileType.pdf:
    case ufv.FileType.excel:
    case ufv.FileType.csv:
    case ufv.FileType.md:
      return _PreviewKind.document;
    case ufv.FileType.word:
      // Legacy binary .doc has no in-app renderer.
      return p.extension(path).toLowerCase() == '.docx'
          ? _PreviewKind.document
          : null;
    default:
      return null;
  }
}

Future<void> _open(BuildContext context, String path) async {
  if (!await openFile(path) && context.mounted) {
    toast(context, 'common.no_app_open'.tr(), type: ToastType.error);
  }
}

void _share(String path) =>
    SharePlus.instance.share(ShareParams(files: [XFile(path)]));

// ---------------------------------------------------------------------------
// Full-screen viewer
// ---------------------------------------------------------------------------

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.path,
    required this.name,
    required this.kind,
  });

  final String path;
  final String name;
  final _PreviewKind kind;

  @override
  Widget build(BuildContext context) {
    final body = switch (kind) {
      _PreviewKind.image => PhotoView(
        imageProvider: FileImage(File(path)),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        initialScale: PhotoViewComputedScale.contained,
        loadingBuilder: (_, _) =>
            const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, _, _) => const _PreviewError(),
      ),
      _PreviewKind.video => _VideoPlayerView(path: path),
      _PreviewKind.videoPoster => _VideoPoster(path: path),
      // Documents render as paper: universal_file_viewer's viewers assume a
      // light theme, so they get one regardless of the app's. The Material
      // matters as much as the Theme — it resets the inherited DefaultTextStyle,
      // which is otherwise the dark app's white and hides unstyled DOCX text.
      _PreviewKind.document => Theme(
        data: ThemeData.light(useMaterial3: true),
        child: Material(
          color: Colors.white,
          child: ufv.UniversalFileViewer(
            file: File(path),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ),
      ),
      _PreviewKind.text => _TextView(path: path),
    };
    // Images and video play full-bleed under the floating bar; documents and
    // text start below it so the first lines are not hidden.
    final fullBleed =
        kind == _PreviewKind.image ||
        kind == _PreviewKind.video ||
        kind == _PreviewKind.videoPoster;
    final bar = _TopBar(
      name: name,
      onOpen: kind == _PreviewKind.image ? null : () => _open(context, path),
      onShare: () => _share(path),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: fullBleed
          ? Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(top: 0, left: 0, right: 0, child: bar),
              ],
            )
          : Column(
              children: [
                bar,
                Expanded(child: body),
              ],
            ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.name, required this.onShare, this.onOpen});

  final String name;
  final VoidCallback onShare;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
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
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
                ),
              ),
            ),
            if (onOpen != null) ...[
              _RoundButton(
                icon: AppIcons.externalLink,
                onTap: () {
                  tapHaptic();
                  onOpen!();
                },
              ),
              const SizedBox(width: 8),
            ],
            _RoundButton(
              icon: AppIcons.shareLink,
              onTap: () {
                tapHaptic();
                onShare();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular, semi-transparent overlay button for the viewer's top bar.
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

class _PreviewError extends StatelessWidget {
  const _PreviewError();

  @override
  Widget build(BuildContext context) => const Center(
    child: AppSvgIcon(AppIcons.imageOff, size: 48, color: Colors.white54),
  );
}

// ---------------------------------------------------------------------------
// Video
// ---------------------------------------------------------------------------

/// In-app player: tap toggles the controls, the bar scrubs.
class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.path});

  final String path;

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _controller;
  bool _failed = false;
  bool _controls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _controller.addListener(_onTick);
    _controller.initialize().then(
      (_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
  }

  void _onTick() {
    if (!mounted) return;
    if (_controller.value.hasError && !_failed) {
      setState(() => _failed = true);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    tapHaptic();
    final v = _controller.value;
    if (v.isPlaying) {
      _controller.pause();
    } else {
      if (v.duration > Duration.zero && v.position >= v.duration) {
        _controller.seekTo(Duration.zero);
      }
      _controller.play();
    }
  }

  static String _clock(Duration d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    // A codec the platform player can't handle: fall back to the poster, which
    // hands the file to the system player.
    if (_failed) return _VideoPoster(path: widget.path);
    final v = _controller.value;
    if (!v.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _controls = !_controls),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: v.aspectRatio > 0 ? v.aspectRatio : 16 / 9,
              child: VideoPlayer(_controller),
            ),
          ),
          if (_controls || !v.isPlaying) ...[
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                  child: Icon(
                    v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 44,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Text(
                        _clock(v.position),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          colors: const VideoProgressColors(
                            playedColor: Colors.white,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _clock(v.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plain text
// ---------------------------------------------------------------------------

class _TextView extends StatefulWidget {
  const _TextView({required this.path});

  final String path;

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView> {
  late final Future<String> _text = File(widget.path)
      .readAsBytes()
      .then((b) => utf8.decode(b, allowMalformed: true));

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0B0F17),
      child: FutureBuilder<String>(
        future: _text,
        builder: (context, snap) {
          if (snap.hasError) return const _PreviewError();
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.paddingOf(context).bottom,
            ),
            child: SelectableText(
              snap.data!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          );
        },
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
