import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_bottom_nav.dart' show AppNavItem;
import 'app_format.dart';
import 'app_responsive.dart';
import 'app_svg_icon.dart';

/// The side navigation for desktop and tablet landscape (the wide-layout
/// counterpart to [AppBottomNav]): the wordmark, then the destinations, the
/// active one on a sunken pill with the accent icon.
///
/// On an open iPhone Duo ([isFoldableSize]) the rail is compact: icons over
/// short labels in a narrow column, so the content keeps most of the width.
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

  /// Width of the compact rail.
  static const double compactWidth = 84;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (context.isFoldableOpen) {
      // The rail stands on the leading side, which is the right in Arabic,
      // where the iPhone Duo keeps its status strip: it takes that strip's
      // inset on whichever side it is.
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final pad = MediaQuery.paddingOf(context);
      return Container(
        width: compactWidth + (rtl ? pad.right : pad.left),
        decoration: BoxDecoration(
          color: t.surface,
          border: BorderDirectional(end: BorderSide(color: t.line)),
        ),
        child: SafeArea(
          left: !rtl,
          right: rtl,
          child: Column(
            children: [
              const SizedBox(height: 18),
              for (var i = 0; i < items.length; i++)
                _CompactRailItem(
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

/// The tabs as a column in the system's side strip ([sideStripOf]): the
/// iPhone Duo outer display, where the status bar already sits on the right
/// and Apple moves tab bars beside it. [width] is the strip's inset; the items
/// sit in its middle, under the status bar.
class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.width,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++)
            _CompactRailItem(
              item: items[i],
              active: i == currentIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

/// One destination of the compact rail: the icon on a pill, the label under it
/// (the bottom bar's item, stood in a column).
class _CompactRailItem extends StatelessWidget {
  const _CompactRailItem({
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
      child: InkWell(
        onTap: () {
          if (!active) tapHaptic();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 56,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? t.sunken : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AppSvgIcon(item.icon, size: 22, color: color),
                  ),
                  if (item.badge > 0)
                    PositionedDirectional(
                      end: 4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.accentStrong,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          item.badge > 99 ? '99+' : '${item.badge}',
                          style: AppType.small.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: t.onAccent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppType.nav.copyWith(
                    color: active ? t.text : t.text3,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [child] next to the rail. On an open iPhone Duo in a right-to-left
/// language the rail stands on the right and takes the status strip's inset
/// there (AppNavRail), so the content must not leave room for it again.
/// Everywhere else [child] as it is.
Widget besideNavRail(BuildContext context, Widget child) {
  if (!context.isFoldableOpen ||
      Directionality.of(context) != TextDirection.rtl) {
    return child;
  }
  return MediaQuery.removePadding(
    context: context,
    removeRight: true,
    child: child,
  );
}
