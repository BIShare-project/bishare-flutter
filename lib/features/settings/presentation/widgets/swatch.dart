import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

class Swatch extends StatelessWidget {
  const Swatch({super.key, 
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.foreground : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
              : null,
        ),
        child: selected
            ? const AppSvgIcon(AppIcons.check, size: 12, color: Colors.white)
            : null,
      ),
    );
  }
}
