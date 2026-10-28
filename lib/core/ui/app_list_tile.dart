import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';

/// The app-wide list row: optional [leading], a [title] (+ optional
/// [subtitle]), optional [trailing], and tap / long-press. Flat, at least 56
/// tall, the title in the row style and the subtitle in the secondary style;
/// call sites pass plain [Text]/[Widget]s. Replaces Material [ListTile].
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    final t = context.tokens;
    // Sheets and dialogs provide no Material ancestor, so a bare InkWell throws
    // `Material.of` on mouse hover (desktop). A transparent Material gives it
    // the ancestor it needs without changing the visuals.
    return Material(
      type: MaterialType.transparency,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: padding,
            child: Row(
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(color: t.text2),
                    child: leading!,
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle.merge(
                        style: AppType.row.copyWith(color: t.text),
                        child: title,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle.merge(
                          style: AppType.secondary.copyWith(
                            fontSize: 13,
                            color: t.text2,
                          ),
                          child: subtitle!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  IconTheme.merge(
                    data: IconThemeData(color: t.text3),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
