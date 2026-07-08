import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

/// A monochrome rounded-square settings glyph (default color, not tinted).
class Glyph extends StatelessWidget {
  const Glyph(this.icon, {super.key});
  final String icon;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(9),
      ),
      child: AppSvgIcon(icon, size: 22, color: cs.mutedForeground),
    );
  }
}
