import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_format.dart';

/// The app-wide card surface: the one emphasised block of a screen (the
/// profile, the Drive backup, the storage, the room code). Flat surface with
/// a hairline, optionally tappable. Lists are not cards: use [AppGroup] rows.
///
/// [accent] tints the border; [gradient] is kept for old call sites and now
/// draws the soft accent backing instead of a gradient.
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
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tints the border (and, with [gradient], the fill).
  final Color? accent;

  /// A soft accent backing for the screen's hero card.
  final bool gradient;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final br = BorderRadius.circular(radius);
    final fill = gradient
        ? Color.alphaBlend(
            (accent ?? t.accent).withValues(alpha: 0.08),
            t.surface,
          )
        : t.surface;
    return Padding(
      padding: margin,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: br,
            border: Border.all(
              color: accent != null ? accent!.withValues(alpha: 0.4) : t.line,
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
