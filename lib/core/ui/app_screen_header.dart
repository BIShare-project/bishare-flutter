import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_svg_icon.dart';

/// A large-title screen header: a bold title, optional [subtitle], and optional
/// trailing [actions]. Pass [onBack] on a pushed (non-tab) page to show a leading
/// back chevron.
class AppScreenHeader extends StatelessWidget {
  const AppScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// When non-null, a leading back button is shown that calls this.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(onBack != null ? 8 : 20, 10, 12, 8),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ShadIconButton.ghost(
                icon: const AppSvgIcon(AppIcons.chevronLeft, size: 22),
                onPressed: onBack,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: cs.foreground,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 13, color: cs.mutedForeground),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
