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
        // A tap opens the row; on a tablet shadcn would pop the menu too.
        tapEnabled: false,
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

/// Imperatively show [actions] as a sheet (the touch fallback / any
/// explicit "more" affordance): the actions on one card, the destructive
/// ones on a card of their own below. [leading] is the item's picture.
Future<void> showActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? leading,
  required List<AppMenuAction> actions,
}) {
  return showAppSheet<void>(
    context,
    title: title,
    subtitle: subtitle,
    leading: leading,
    builder: (ctx) {
      Widget row(AppMenuAction a) => AppSheetAction(
        icon: a.icon,
        label: a.label,
        destructive: a.destructive,
        onTap: () {
          Navigator.pop(ctx);
          a.onTap();
        },
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetGroup(
            first: true,
            children: [
              for (final a in actions)
                if (!a.destructive) row(a),
            ],
          ),
          AppSheetGroup(
            children: [
              for (final a in actions)
                if (a.destructive) row(a),
            ],
          ),
        ],
      );
    },
  );
}
