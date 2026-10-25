import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';
import 'app_svg_icon.dart';

/// A plain icon button (44 by 44 target) with an optional count badge.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badge = 0,
    this.size = 22,
    this.tooltip,
    this.color,
  });

  /// An [AppIcons] name, rendered with [AppSvgIcon].
  final String icon;
  final VoidCallback onPressed;
  final int badge;
  final double size;

  /// What the button does, shown on long-press / hover and read by screen
  /// readers. Icon-only buttons should always pass one.
  final String? tooltip;

  /// The glyph colour; the primary text colour by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget button = Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: tooltip != null,
      child: SizedBox.square(
        dimension: 44,
        child: Material(
          type: MaterialType.transparency,
          child: InkResponse(
            onTap: () {
              tapHaptic();
              onPressed();
            },
            radius: 22,
            child: Center(
              child: AppSvgIcon(icon, size: size, color: color ?? t.text),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        if (badge > 0)
          PositionedDirectional(
            end: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4.5),
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accentStrong,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: t.bg, width: 1.5),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: AppType.small.copyWith(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: t.onAccent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
