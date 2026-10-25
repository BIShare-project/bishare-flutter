import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_bottom_nav.dart' show AppNavItem;
import 'app_format.dart';
import 'app_svg_icon.dart';

/// The side navigation for desktop and tablet landscape (the wide-layout
/// counterpart to [AppBottomNav]): the wordmark, then the destinations, the
/// active one on a sunken pill with the accent icon.
class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.width = 216,
    this.footer,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double width;

  /// Shown at the bottom of the rail (this device and its visibility).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: t.surface,
        border: BorderDirectional(end: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(22, 22, 20, 14),
              child: Text(
                'BIShare',
                style: AppType.pageTitle.copyWith(
                  color: t.text,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            for (var i = 0; i < items.length; i++)
              _RailItem(
                item: items[i],
                active: i == currentIndex,
                onTap: () => onTap(i),
              ),
            const Spacer(),
            ?footer,
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
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Semantics(
        button: true,
        selected: active,
        child: Material(
          color: active ? t.sunken : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              if (!active) tapHaptic();
              onTap();
            },
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 42),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    AppSvgIcon(
                      item.icon,
                      size: 21,
                      color: active ? t.accent : t.text2,
                      dot: active,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(
                          fontSize: 14.5,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: active ? t.text : t.text2,
                        ),
                      ),
                    ),
                    if (item.badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.accentStrong,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          item.badge > 99 ? '99+' : '${item.badge}',
                          style: AppType.small.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.onAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
