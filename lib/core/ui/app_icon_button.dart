import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';
import 'app_svg_icon.dart';

/// A ghost icon button with an optional count badge (e.g. the inbox action).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badge = 0,
    this.size = 20,
  });

  /// An [AppIcons] name, rendered with [AppSvgIcon].
  final String icon;
  final VoidCallback onPressed;
  final int badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ShadIconButton.ghost(
          icon: AppSvgIcon(icon, size: size),
          onPressed: () {
            tapHaptic();
            onPressed();
          },
        ),
        if (badge > 0)
          Positioned(
            right: 4,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.background, width: 1.5),
              ),
              child: Text(
                '$badge',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: cs.primaryForeground,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
