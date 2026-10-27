import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/deeplink/deep_link.dart';
import '../../../core/deeplink/deep_link_service.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import 'qr_camera.dart';

/// Receiving by code (redesign-plan.md 4.4): the live camera with a scan
/// frame, a torch and close bar, and a panel to type a 6-letter code, paste a
/// link, or receive by QR Beam. A recognised BIShare payload closes the
/// scanner and is dispatched through [DeepLinkService].
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final QrCameraController _controller = QrCameraController();
  final TextEditingController _code = TextEditingController();
  bool _handled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() {
      if (_error != null) setState(() => _error = null);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onCode(String raw) {
    if (_handled) return;
    if (DeepLink.looksLikeBiShare(raw)) _accept(raw);
  }

  void _accept(String payload) {
    if (_handled) return;
    _handled = true;
    tapHaptic();
    context.pop();
    getIt<DeepLinkService>().submit(payload);
  }

  /// A typed code is ambiguous (a stored transfer or a live stream), so it is
  /// dispatched as a code and the receiver tries both.
  void _submitCode() {
    final code = _code.text;
    if (_handled) return;
    if (code.length < 6) {
      setState(() => _error = 'receive.code_short'.tr());
      return;
    }
    _handled = true;
    tapHaptic();
    context.pop();
    getIt<DeepLinkService>().submitCode(code);
  }

  /// A pasted full link keeps its case (its path segments are case
  /// sensitive) and resolves to its exact action; a pasted code fills the
  /// boxes and goes.
  Future<void> _paste() async {
    final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted || raw == null || raw.isEmpty) {
      setState(() => _error = 'receive.paste_nothing'.tr());
      return;
    }
    if (DeepLink.looksLikeBiShare(raw)) return _accept(raw);
    final code = raw.replaceAll(RegExp(r'[-/\s]'), '').toUpperCase();
    if (RegExp(r'^[A-Z0-9]{6,8}$').hasMatch(code)) {
      _code.text = code;
      _submitCode();
    } else {
      setState(() => _error = 'receive.paste_nothing'.tr());
    }
  }

  void _qrBeam() {
    if (_handled) return;
    _handled = true;
    context.pushReplacement('/qr-beam/receive');
  }

  @override
  Widget build(BuildContext context) {
    // Dark full-screen page: light status-bar icons whatever the app theme.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            QrCamera(
              controller: _controller,
              onCode: _onCode,
              denied: const _CameraDenied(),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black26),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _TopBar(controller: _controller),
                  // The frame centres on the camera area above the panel.
                  const Expanded(child: Center(child: _ScanFrame())),
                  ReceiveTone(
                    child: _Panel(
                      code: _code,
                      error: _error,
                      onSubmit: _submitCode,
                      onPaste: _paste,
                      onQrBeam: _qrBeam,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final QrCameraController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          _CircleButton(
            icon: AppIcons.close,
            onTap: () {
              tapHaptic();
              context.pop();
            },
          ),
          const Spacer(),
          Text(
            'scanner.title'.tr(),
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: controller,
            builder: (context, on, _) {
              return _CircleButton(
                icon: on ? AppIcons.flashlight : AppIcons.flashlightOff,
                active: on,
                onTap: () {
                  tapHaptic();
                  controller.toggleTorch();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: AppSvgIcon(
          icon,
          size: 20,
          color: active ? Colors.black : Colors.white,
        ),
      ),
    );
  }
}

/// The accent scan window: a rounded outline with four corner brackets.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    // White reads on any camera image; the frame shrinks on a short screen.
    return LayoutBuilder(
      builder: (context, c) {
        final side = (c.maxHeight - 24).clamp(120.0, 230.0);
        return RepaintBoundary(
          child: SizedBox(
            width: side,
            height: side,
            child: CustomPaint(painter: _FramePainter(Colors.white)),
          ),
        );
      },
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final bracket = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 34.0;
    const r = 20.0;
    void corner(double x, double y, double dx, double dy) {
      final path = Path()
        ..moveTo(x + dx * len, y)
        ..lineTo(x + dx * r, y)
        ..arcToPoint(
          Offset(x, y + dy * r),
          radius: const Radius.circular(r),
          clockwise: dx == dy,
        )
        ..lineTo(x, y + dy * len);
      canvas.drawPath(path, bracket);
    }

    corner(0, 0, 1, 1); // top-left
    corner(size.width, 0, -1, 1); // top-right
    corner(0, size.height, 1, -1); // bottom-left
    corner(size.width, size.height, -1, -1); // bottom-right
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}

/// The code panel under the camera.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.code,
    required this.error,
    required this.onSubmit,
    required this.onPaste,
    required this.onQrBeam,
  });

  final TextEditingController code;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onPaste;
  final VoidCallback onQrBeam;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 8 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'scanner.hint_title'.tr(),
              style: AppType.pageTitle.copyWith(color: t.text),
            ),
            const SizedBox(height: 2),
            Text(
              'scanner.hint_body'.tr(),
              style: AppType.secondary.copyWith(color: t.text2),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Divider(color: t.line, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'receive.or_code'.tr(),
                    style: AppType.small.copyWith(color: t.text3),
                  ),
                ),
                Expanded(child: Divider(color: t.line, height: 1)),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: AppCodeBoxes(
                controller: code,
                length: 6,
                maxLength: 8,
                autofocus: false,
                error: error != null,
                onSubmitted: (_) => onSubmit(),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: AppType.small.copyWith(color: t.danger),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'home.paste'.tr(),
                    icon: AppIcons.clipboardPaste,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.large,
                    onPressed: onPaste,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'common.download'.tr(),
                    size: AppButtonSize.large,
                    onPressed: onSubmit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppValueRow(
              icon: AppIcons.qrShare,
              title: 'receive.by_qr_beam'.tr(),
              subtitle: 'receive.by_qr_beam_hint'.tr(),
              onTap: onQrBeam,
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraDenied extends StatelessWidget {
  const _CameraDenied();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppSvgIcon(
                AppIcons.cameraOff,
                color: Colors.white54,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'scanner.camera_denied'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
