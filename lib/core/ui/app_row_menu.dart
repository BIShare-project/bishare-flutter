import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';
import 'app_responsive.dart';
import 'app_sheet.dart';
import 'app_svg_icon.dart';

/// One action in a row's context menu.
class AppMenuAction {
  const AppMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

/// Surfaces [actions] for a list row adaptively: a **right-click context menu**
/// on desktop / tablet-landscape, and a **long-press glass sheet** on touch.
/// Wrap the row's tappable content (e.g. an [AppListTile]) with this.
class AppRowMenu extends StatelessWidget {
  const AppRowMenu({
    super.key,
    required this.child,
    required this.actions,
    required this.title,
    this.subtitle,
  });

  final Widget child;
  final List<AppMenuAction> actions;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    if (context.isWideLayout) {
      final cs = ShadTheme.of(context).colorScheme;
      return ShadContextMenuRegion(
        items: [
          for (final a in actions)
            ShadContextMenuItem(
              leading: AppSvgIcon(
                a.icon,
                size: 16,
                color: a.destructive ? cs.destructive : null,
              ),
              onPressed: () {
                tapHaptic();
                a.onTap();
              },
              child: Text(
                a.label,
                style: a.destructive ? TextStyle(color: cs.destructive) : null,
              ),
            ),
        ],
        child: child,
      );
    }
    return GestureDetector(
      onLongPress: () {
        tapHaptic();
        showActionSheet(
          context,
          title: title,
          subtitle: subtitle,
          actions: actions,
        );
      },
      child: child,
    );
  }
}

/// Imperatively show [actions] as a glass sheet (the touch fallback / any
/// explicit "more" affordance).
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<AppMenuAction> actions,
}) {
  return showAppSheet<void>(
    context,
    title: title,
    subtitle: subtitle,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in actions)
          AppSheetAction(
            icon: a.icon,
            label: a.label,
            destructive: a.destructive,
            onTap: () {
              Navigator.pop(ctx);
              a.onTap();
            },
          ),
      ],
    ),
  );
}
