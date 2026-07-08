import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

/// One feature slide of the onboarding walkthrough: a gradient-glow icon orb, a
/// bold title and a muted description — mirrors the native `OnboardingView`.
class OnboardingSlide extends StatelessWidget {
  const OnboardingSlide({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });

  final String icon;
  final String title;
  final String description;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 168,
            height: 168,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer radial glow.
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        color.withValues(alpha: 0.22),
                        color.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: const SizedBox(width: 168, height: 168),
                ),
                // Main gradient orb.
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(color, Colors.white, 0.18)!,
                        color,
                        Color.lerp(color, Colors.black, 0.12)!,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: AppSvgIcon(icon, size: 48, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: cs.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
