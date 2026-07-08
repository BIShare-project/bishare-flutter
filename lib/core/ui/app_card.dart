import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';

/// The app-wide card surface: rounded, hairline-bordered, optionally tappable,
/// with an [accent] border tint or a subtle [gradient] hero fill. Replaces raw
/// Material [Card]/[Container] use across the app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 4),
    this.onTap,
    this.onLongPress,
    this.accent,
    this.gradient = false,
    this.radius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tints the border (and, with [gradient], the fill).
  final Color? accent;

  /// A subtle accent gradient fill for hero cards.
  final bool gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final tint = accent ?? cs.primary;
    final br = BorderRadius.circular(radius);
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: gradient ? null : cs.card,
            gradient: gradient
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.14),
                      tint.withValues(alpha: 0.04),
                    ],
                  )
                : null,
            borderRadius: br,
            border: Border.all(
              color: gradient
                  ? tint.withValues(alpha: 0.22)
                  : accent != null
                  ? tint.withValues(alpha: 0.35)
                  : cs.border.withValues(alpha: 0.8),
            ),
          ),
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    tapHaptic();
                    onTap!();
                  },
            onLongPress: onLongPress == null
                ? null
                : () {
                    tapHaptic();
                    onLongPress!();
                  },
            borderRadius: br,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
