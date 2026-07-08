import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_format.dart';
import 'app_svg_icon.dart';

/// One destination in an [AppBottomNav].
class AppNavItem {
  const AppNavItem({required this.icon, required this.label, this.badge = 0});

  /// An [AppIcons] name — the destination is drawn with an [AppSvgIcon].
  final String icon;
  final String label;
  final int badge;
}

/// A premium frosted-glass tab bar (iOS-style): translucent blurred surface, a
/// hairline top border, and accent-tinted active items with an optional badge.
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
    final cs = ShadTheme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: cs.background.withValues(alpha: 0.82),
            border: Border(
              top: BorderSide(color: cs.border.withValues(alpha: 0.6)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
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
    final cs = ShadTheme.of(context).colorScheme;
    final color = active ? cs.primary : cs.mutedForeground;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tapHaptic();
        onTap();
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppSvgIcon(item.icon, size: 24, color: color),
              if (item.badge > 0)
                Positioned(
                  right: -7,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 15),
                    decoration: BoxDecoration(
                      color: cs.destructive,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.background, width: 1.5),
                    ),
                    child: Text(
                      '${item.badge}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: cs.destructiveForeground,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
