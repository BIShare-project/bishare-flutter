import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

import 'app_svg_icon.dart';

/// A rounded-square device avatar with an accent gradient and an optional online
/// dot — the app-wide stand-in for Material's [CircleAvatar]. Reads closer to
/// SF-Symbols-in-a-squircle than a flat circle.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.icon,
    this.size = 46,
    this.online = false,
    this.accent,
  });

  final String icon;
  final double size;
  final bool online;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dot = size * 0.24;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // No background tile — the glyph is shown as-is (its own duotone),
          // optionally tinted by [accent].
          Center(
            child: AppSvgIcon(icon, size: size * 0.82, color: accent),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: t.ok,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
