import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';
import 'app_svg_icon.dart';

/// One destination in an [AppBottomNav].
class AppNavItem {
  const AppNavItem({required this.icon, required this.label, this.badge = 0});

  /// An [AppIcons] name: the destination is drawn with an [AppSvgIcon].
  final String icon;
  final String label;
  final int badge;
}

/// The phone tab bar: a solid bar with a hairline on top (no blur, which is
/// the most expensive effect Flutter draws), the accent and its corner dot on
/// the active tab only, and an optional count badge.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    active: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = active ? t.accent : t.text3;
    return Semantics(
      button: true,
      selected: active,
      label: item.badge > 0 ? '${item.label}, ${item.badge}' : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: () {
          if (!active) tapHaptic();
          onTap();
        },
        radius: 36,
        highlightShape: BoxShape.circle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppSvgIcon(item.icon, size: 24, color: color, dot: active),
                if (item.badge > 0)
                  PositionedDirectional(
                    end: -9,
                    top: -5,
                    child: _Badge(count: item.badge),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // One line, always: a long label ("Bandeja de entrada") wrapped to
            // two lines and pushed the bar past its height.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.nav.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.5),
      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
      decoration: BoxDecoration(
        color: t.danger,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.bg, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppType.small.copyWith(
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: t.onDanger,
        ),
      ),
    );
  }
}
