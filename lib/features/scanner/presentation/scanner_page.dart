import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/constants/cloud.dart';
import '../../../core/deeplink/deep_link.dart';
import '../../../core/deeplink/deep_link_service.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';

/// Full-screen QR scanner — a faithful port of the native iOS `QRScannerView`:
/// live camera, an accent scan frame with corner brackets, a torch + close bar,
/// and a glass status card that lists what can be scanned plus manual code
/// entry. A recognised BIShare payload closes the scanner and is dispatched
/// through [DeepLinkService].
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _manual = TextEditingController();
  bool _handled = false;
  bool _showManual = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && DeepLink.looksLikeBiShare(raw)) {
        _accept(raw);
        return;
      }
    }
  }

  void _accept(String payload) {
    if (_handled) return;
    _handled = true;
    tapHaptic();
    context.pop();
    getIt<DeepLinkService>().submit(payload);
  }

  void _submitManual() {
    final code = _manual.text.trim().toUpperCase();
    if (code.length < 4) return;
    // A pasted full link is dispatched as-is; a bare code is treated as a 24h
    // cloud-transfer code (the receive path P3-A supports).
    final payload = DeepLink.looksLikeBiShare(code)
        ? code
        : CloudConfig.transferWebUrl(code);
    _accept(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const _CameraDenied(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(color: Colors.black26),
          ),
          const Center(child: _ScanFrame()),
          SafeArea(
            child: Column(
              children: [
                _TopBar(controller: _controller),
                const Spacer(),
                _StatusCard(
                  showManual: _showManual,
                  manual: _manual,
                  onToggleManual: () =>
                      setState(() => _showManual = !_showManual),
                  onSubmit: _submitManual,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final MobileScannerController controller;

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
          const Text(
            'Scan QR code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: controller,
            builder: (context, state, _) {
              final on = state.torchState == TorchState.on;
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
    final accent = ShadTheme.of(context).colorScheme.primary;
    return SizedBox(
      width: 250,
      height: 250,
      child: CustomPaint(painter: _FramePainter(accent)),
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

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.showManual,
    required this.manual,
    required this.onToggleManual,
    required this.onSubmit,
  });

  final bool showManual;
  final TextEditingController manual;
  final VoidCallback onToggleManual;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final accent = ShadTheme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Point at a BIShare QR code',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Transfers, share links and rooms',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),
          if (showManual)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: manual,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => onSubmit(),
                    decoration: InputDecoration(
                      hintText: 'ABC123',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.1),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onSubmit,
                  child: AppSvgIcon(AppIcons.arrowRightCircle, color: accent, size: 34),
                ),
              ],
            )
          else
            GestureDetector(
              onTap: onToggleManual,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppSvgIcon(
                    AppIcons.keyboard,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Enter code manually',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
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
              const AppSvgIcon(AppIcons.cameraOff, color: Colors.white54, size: 48),
              const SizedBox(height: 16),
              Text(
                'Camera access is needed to scan QR codes',
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
