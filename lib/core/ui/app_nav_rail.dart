import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_bottom_nav.dart' show AppNavItem;
import 'app_format.dart';
import 'app_svg_icon.dart';

/// A desktop / tablet-landscape side navigation rail (the wide-layout counterpart
/// to [AppBottomNav]). Brand wordmark on top, then vertical nav items with an
/// accent-tinted pill for the active one and an optional count badge.
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.width = 236,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: cs.card,
        border: Border(
          right: BorderSide(color: cs.border.withValues(alpha: 0.7)),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 20, 18),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          cs.primary,
                          Color.lerp(cs.primary, Colors.black, 0.24)!,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const AppSvgIcon(
                      AppIcons.send,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'BIShare',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: cs.foreground,
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              _RailItem(
                item: items[i],
                active: i == currentIndex,
                onTap: () => onTap(i),
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final color = active ? cs.primary : cs.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            tapHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: active ? cs.primary.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AppSvgIcon(item.icon, size: 22, color: color),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? cs.foreground : cs.mutedForeground,
                  ),
                ),
                const Spacer(),
                if (item.badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${item.badge}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: cs.primaryForeground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
