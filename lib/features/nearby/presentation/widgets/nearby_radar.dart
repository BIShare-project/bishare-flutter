import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/nearby_peer.dart';

/// A premium sonar radar: a glowing gradient core (this device), continuously
/// expanding pulse ripples, a rotating sweep with a light trail, and discovered
/// peers as glass nodes on an orbit — each linked to the core by an animated
/// beam while connecting/transferring. Peers glide into place and fade in.
class NearbyRadar extends StatefulWidget {
  const NearbyRadar({super.key, required this.peers, required this.onTapPeer});

  final List<NearbyPeer> peers;
  final void Function(NearbyPeer) onTapPeer;

  @override
  State<NearbyRadar> createState() => _NearbyRadarState();
}

class _NearbyRadarState extends State<NearbyRadar>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat();
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = cs.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final center = Offset(w / 2, h / 2);
        final maxR = math.min(w, h) / 2 - 46;
        final orbitR = maxR * 0.84;
        final positions = [
          for (var i = 0; i < widget.peers.length; i++)
            _orbit(i, widget.peers.length, orbitR, center),
        ];

        return Stack(
          alignment: Alignment.center,
          children: [
            // Rings + ripples + sweep + connection beams.
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulse, _sweep]),
                builder: (context, _) => CustomPaint(
                  size: Size(w, h),
                  painter: _RadarPainter(
                    center: center,
                    maxR: maxR,
                    pulse: _pulse.value,
                    sweep: _sweep.value,
                    accent: accent,
                    ring: cs.mutedForeground.withValues(alpha: isDark ? 0.22 : 0.18),
                    isDark: isDark,
                    beams: [
                      for (var i = 0; i < widget.peers.length; i++)
                        if (widget.peers[i].isBusy ||
                            widget.peers[i].state == NearbyPeerState.connected)
                          positions[i],
                    ],
                  ),
                ),
              ),
            ),

            // The core (this device) — a pulsing gradient orb.
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final t = math.sin(_pulse.value * 2 * math.pi);
                final scale = 1 + 0.05 * t;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(accent, Colors.white, 0.22)!,
                          accent,
                          Color.lerp(accent, Colors.black, 0.18)!,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.55 + 0.15 * t),
                          blurRadius: 26 + 6 * t,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const AppSvgIcon(
                      AppIcons.smartphone,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),

            // Peer nodes — glide + fade into orbit.
            for (var i = 0; i < widget.peers.length; i++)
              AnimatedPositioned(
                key: ValueKey(widget.peers[i].id),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                left: positions[i].dx - 37,
                top: positions[i].dy - 37,
                width: 74,
                height: 74,
                child: _PeerNode(
                  peer: widget.peers[i],
                  accent: accent,
                  onTap: () => widget.onTapPeer(widget.peers[i]),
                ),
              ),
          ],
        );
      },
    );
  }

  static Offset _orbit(int index, int count, double radius, Offset center) {
    // Evenly spaced, starting at the top. A single peer sits top-right so it
    // doesn't hide behind the core's label.
    final angle = count == 1
        ? -math.pi / 3
        : (2 * math.pi * index) / count - math.pi / 2;
    return Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
  }
}

class _PeerNode extends StatelessWidget {
  const _PeerNode({required this.peer, required this.accent, required this.onTap});
  final NearbyPeer peer;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final busy = peer.isBusy;
    final live = busy || peer.state == NearbyPeerState.connected;
    return TweenAnimationBuilder<double>(
      // Scale + fade in on discovery.
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.scale(scale: 0.6 + 0.4 * t.clamp(0, 1), child: child),
      ),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.card,
                    Color.lerp(cs.card, accent, live ? 0.16 : 0.0)!,
                  ],
                ),
                border: Border.all(
                  color: live ? accent : cs.border,
                  width: live ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: live
                        ? accent.withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.18),
                    blurRadius: live ? 16 : 8,
                  ),
                ],
              ),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(accent),
                      ),
                    )
                  : AppSvgIcon(AppIcons.user, size: 22, color: cs.foreground),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 72,
              child: Text(
                peer.alias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: live ? cs.foreground : cs.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.center,
    required this.maxR,
    required this.pulse,
    required this.sweep,
    required this.accent,
    required this.ring,
    required this.isDark,
    required this.beams,
  });

  final Offset center;
  final double maxR;
  final double pulse; // 0..1
  final double sweep; // 0..1
  final Color accent;
  final Color ring;
  final bool isDark;
  final List<Offset> beams;

  @override
  void paint(Canvas canvas, Size size) {
    // Ambient core glow.
    canvas.drawCircle(
      center,
      maxR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: isDark ? 0.16 : 0.10),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxR)),
    );

    // Static orbit rings.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, maxR * i / 3, ringPaint);
    }

    // Expanding pulse ripples (staggered).
    const count = 3;
    for (var i = 0; i < count; i++) {
      final phase = (pulse + i / count) % 1.0;
      final r = phase * maxR;
      final alpha = (1 - phase) * (isDark ? 0.5 : 0.38);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent.withValues(alpha: alpha),
      );
    }

    // Rotating sweep cone + leading edge.
    final angle = sweep * 2 * math.pi;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final cone = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi / 2.4,
        colors: [
          accent.withValues(alpha: isDark ? 0.30 : 0.22),
          accent.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: maxR));
    canvas.drawCircle(Offset.zero, maxR, cone);
    canvas.drawLine(
      Offset.zero,
      Offset(maxR, 0),
      Paint()
        ..strokeWidth = 1.6
        ..color = accent.withValues(alpha: 0.6),
    );
    canvas.restore();

    // Beams to live peers, with a travelling packet.
    for (final p in beams) {
      final grad = Paint()
        ..shader = LinearGradient(
          colors: [
            accent.withValues(alpha: 0.6),
            accent.withValues(alpha: 0.12),
          ],
        ).createShader(Rect.fromPoints(center, p))
        ..strokeWidth = 1.6;
      canvas.drawLine(center, p, grad);
      // Packet travelling outward along the beam.
      final tt = pulse % 1.0;
      final packet = Offset.lerp(center, p, tt)!;
      canvas.drawCircle(
        packet,
        3,
        Paint()..color = accent.withValues(alpha: (1 - tt).clamp(0.15, 0.9)),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.pulse != pulse ||
      old.sweep != sweep ||
      old.beams.length != beams.length ||
      old.maxR != maxR;
}
