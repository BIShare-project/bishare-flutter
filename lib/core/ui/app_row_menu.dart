import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';

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
      final t = context.tokens;
      // Right click opens the actions as a menu at the pointer; a tap
      // still opens the row.
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) async {
          final o = d.globalPosition;
          final picked = await showMenu<AppMenuAction>(
            context: context,
            color: t.raised,
            position: RelativeRect.fromLTRB(o.dx, o.dy, o.dx, o.dy),
            items: [
              for (final a in actions)
                PopupMenuItem(
                  value: a,
                  height: 40,
                  child: Row(
                    children: [
                      AppSvgIcon(
                        a.icon,
                        size: 16,
                        color: a.destructive ? t.danger : t.text2,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        a.label,
                        style: AppType.body.copyWith(
                          color: a.destructive ? t.danger : t.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
          if (picked == null) return;
          tapHaptic();
          picked.onTap();
        },
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
/// explicit "more" affordance): the actions in one flat group, the
/// destructive ones in a group of their own below. [leading] is the item's picture.
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
      final plain = actions.any((a) => !a.destructive);
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
            first: !plain,
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
