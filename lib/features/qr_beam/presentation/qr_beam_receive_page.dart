import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/ui/app_ui.dart';
import '../domain/beam_codec.dart';

/// QR Beam receiver — scans the sender's cycling QR stream, reassembles the
/// file, and drops it into the same inbox/history as a LAN or Nearby transfer
/// (via [TransferServer.ingestExternalFile]).
class QrBeamReceivePage extends StatefulWidget {
  const QrBeamReceivePage({super.key});

  @override
  State<QrBeamReceivePage> createState() => _QrBeamReceivePageState();
}

class _QrBeamReceivePageState extends State<QrBeamReceivePage> {
  // unrestricted: deliver every readable frame (noDuplicates/normal would debounce
  // the cycling stream and drop frames we still need). The collector dedupes.
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.unrestricted,
  );
  final BeamCollector _collector = BeamCollector();

  int _received = 0;
  int _total = 0;
  bool _finishing = false;
  String? _savedName;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_finishing) return;
    var changed = false;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && _collector.add(raw)) changed = true;
    }
    if (changed) {
      setState(() {
        _received = _collector.received;
        _total = _collector.total;
      });
      if (_collector.complete) _finish();
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await _controller.stop();
      final bytes = _collector.assemble();
      final meta = _collector.meta!;
      final dir = await getTemporaryDirectory();
      final tmp = File(
        '${dir.path}/qrbeam_${DateTime.now().millisecondsSinceEpoch}_${meta.name}',
      );
      await tmp.writeAsBytes(bytes, flush: true);
      final saved = await getIt<TransferServer>().ingestExternalFile(
        tempPath: tmp.path,
        fileName: meta.name,
        fileType: meta.mime,
        size: meta.size,
        senderAlias: 'qr_beam.sender'.tr(),
      );
      if (!mounted) return;
      setState(() => _savedName = saved?.fileName ?? meta.name);
      tapHaptic();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'qr_beam.err_save'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _savedName != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!done)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => const _CameraDenied(),
            ),
          if (!done) const DecoratedBox(decoration: BoxDecoration(color: Colors.black26)),
          if (!done) const Center(child: _ScanFrame()),
          SafeArea(
            child: Column(
              children: [
                _TopBar(controller: _controller, showTorch: !done),
                const Spacer(),
                if (done)
                  _DoneCard(name: _savedName!)
                else
                  _ProgressCard(received: _received, total: _total, error: _error),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.received, required this.total, this.error});

  final int received;
  final int total;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final scanning = total == 0;
    final pct = total == 0 ? 0.0 : received / total;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppSvgIcon(AppIcons.scanDocument, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  scanning ? 'qr_beam.aim'.tr() : 'qr_beam.receiving'.tr(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              if (!scanning)
                Text('${(pct * 100).round()}%',
                    style: TextStyle(fontSize: 13, color: cs.mutedForeground)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: scanning ? null : pct,
              minHeight: 6,
              backgroundColor: cs.muted,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            scanning
                ? 'qr_beam.aim_hint'.tr()
                : 'qr_beam.chunks_of'.tr(namedArgs: {'i': '$received', 'n': '$total'}),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.mutedForeground),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: TextStyle(fontSize: 12.5, color: cs.destructive)),
          ],
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: AppSvgIcon(AppIcons.successSent, size: 22, color: cs.primary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('qr_beam.received_title'.tr(),
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.mutedForeground)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'qr_beam.done'.tr(),
            icon: AppIcons.check,
            fullWidth: true,
            onPressed: () {
              tapHaptic();
              context.pop();
            },
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller, required this.showTorch});

  final MobileScannerController controller;
  final bool showTorch;

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
            'qr_beam.receive_title'.tr(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (showTorch)
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
            )
          else
            const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap, this.active = false});

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
        child: AppSvgIcon(icon, size: 20, color: active ? Colors.black : Colors.white),
      ),
    );
  }
}

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
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const r = 20.0;
    const len = 34.0;
    final w = size.width, h = size.height;
    // Four corner brackets.
    void corner(Offset o, Offset h1, Offset v1) {
      canvas.drawLine(o, o + h1, paint);
      canvas.drawLine(o, o + v1, paint);
    }
    corner(const Offset(0, r), const Offset(0, 0), const Offset(0, len));
    canvas.drawLine(const Offset(r, 0), Offset(r + len, 0), paint);
    canvas.drawLine(Offset(w - r, 0), Offset(w - r - len, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, r + len), paint);
    canvas.drawLine(Offset(0, h - r), Offset(0, h - r - len), paint);
    canvas.drawLine(Offset(r, h), Offset(r + len, h), paint);
    canvas.drawLine(Offset(w, h - r), Offset(w, h - r - len), paint);
    canvas.drawLine(Offset(w - r, h), Offset(w - r - len, h), paint);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.color != color;
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
          child: AppEmptyState(
            icon: AppIcons.cameraOff,
            title: 'qr_beam.camera_denied_title'.tr(),
            message: 'qr_beam.camera_denied_msg'.tr(),
          ),
        ),
      ),
    );
  }
}
