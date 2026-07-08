import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';

/// The app-wide list row: optional [leading], a [title] (+ optional [subtitle]),
/// optional [trailing], and tap / long-press. Typography follows the app scale,
/// so call sites pass plain [Text]/[Widget]s. Replaces Material [ListTile].
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  });

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return InkWell(
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
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: cs.foreground,
                    ),
                    child: title,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.mutedForeground,
                      ),
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
