import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_svg_icon.dart';

/// What a [AppDeviceAvatar]'s ring shows.
enum AppTransferRing { none, running, done, failed }

/// A device in a circle, the same in the radar, the device list and the
/// transfer card: the device glyph, an optional favourite mark, and a
/// progress ring (the BIShare line gradient) while sending or receiving. The
/// ring is a painter in its own repaint boundary, so progress repaints the
/// ring only.
class AppDeviceAvatar extends StatelessWidget {
  const AppDeviceAvatar({
    super.key,
    required this.icon,
    this.size = 60,
    this.ring = AppTransferRing.none,
    this.progress = 0,
    this.favourite = false,
    this.highlight = false,
  });

  final String icon;
  final double size;
  final AppTransferRing ring;

  /// 0 to 1 while [ring] is running.
  final double progress;
  final bool favourite;

  /// This device (accent backing) rather than a peer.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final done = ring == AppTransferRing.done;
    return SizedBox.square(
      dimension: size + 8,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? t.accentStrong
                  : highlight
                  ? t.accentSoft
                  : t.sunken,
            ),
            alignment: Alignment.center,
            child: AppSvgIcon(
              done ? AppIcons.check : icon,
              size: size * 0.46,
              color: done
                  ? t.onAccent
                  : highlight
                  ? t.accent
                  : t.text,
            ),
          ),
          if (ring == AppTransferRing.running || ring == AppTransferRing.failed)
            RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size + 8),
                painter: _RingPainter(
                  progress: ring == AppTransferRing.failed
                      ? progress
                      : progress.clamp(0, 1),
                  track: t.line,
                  gradient: ring == AppTransferRing.failed ? null : t.brandLine,
                  failed: ring == AppTransferRing.failed ? t.danger : null,
                ),
              ),
            ),
          if (favourite)
            PositionedDirectional(
              top: 0,
              end: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: t.raised,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AppSvgIcon(
                  AppIcons.starFavorite,
                  size: 13,
                  color: t.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.track,
    required this.gradient,
    required this.failed,
  });

  final double progress;
  final Color track;
  final Gradient? gradient;
  final Color? failed;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final sweep = math.pi * 2 * progress;
    if (sweep <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (failed != null) {
      paint.color = failed!;
    } else {
      paint.shader = gradient!.createShader(rect);
    }
    canvas.drawArc(r, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.failed != failed || old.track != track;
}
