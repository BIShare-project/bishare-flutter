import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';

/// One content tab, with the number of items selected in it (0 hides it).
class AppTab {
  const AppTab(this.label, {this.count = 0});

  final String label;
  final int count;
}

/// Content tabs under a screen title (Foto, Video, Audio, ...): scrollable,
/// a sliding accent underline, a hairline below, and a small count badge per
/// tab. Built on Material's [TabBar], whose indicator moves by painting only
/// (no layout per frame). Needs a [TabController] from [controller] or a
/// [DefaultTabController] above.
class AppTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTabBar({super.key, required this.tabs, this.controller, this.onTap});

  final List<AppTab> tabs;
  final TabController? controller;
  final ValueChanged<int>? onTap;

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 10),
        dividerHeight: 0,
        overlayColor: WidgetStatePropertyAll(t.accent.withValues(alpha: 0.06)),
        splashBorderRadius: BorderRadius.circular(10),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: t.accent, width: 2),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
        labelColor: t.text,
        unselectedLabelColor: t.text2,
        labelStyle: AppType.row.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppType.row,
        onTap: (i) {
          tapHaptic();
          onTap?.call(i);
        },
        tabs: [
          for (final tab in tabs)
            Tab(
              height: 46,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tab.label),
                  if (tab.count > 0) ...[
                    const SizedBox(width: 6),
                    _Count(tab.count),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // A fixed height: inside a Tab the row is as tall as the tab, and an
    // aligned Container would stretch to it.
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accentStrong,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        n > 99 ? '99+' : '$n',
        style: AppType.small.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: t.onAccent,
        ),
      ),
    );
  }
}

/// A segmented control (two or three choices): neutral, the chosen segment
/// raised on a sunken track. The accent stays for actions.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 14),
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final (v, label) in options)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: v == value,
                  // InkWell, not a bare gesture: it takes keyboard focus
                  // and Enter/Space on desktop.
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () {
                      if (v == value) return;
                      tapHaptic();
                      onChanged(v);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 38),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: v == value
                          ? BoxDecoration(
                              // Raised alone sits too close to the sunken
                              // track in dark; the line colour reads as lifted.
                              color: t.isDark ? t.line : t.surface,
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1F000000),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            )
                          : null,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(
                          fontSize: 14,
                          fontWeight: v == value
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: v == value ? t.text : t.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A row of filter chips that scrolls sideways. The chosen chip is filled with
/// the text colour (neutral, not the accent).
class AppChips<T> extends StatelessWidget {
  const AppChips({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Start-aligned even inside a centring Column.
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (final (v, label) in options) ...[
              Semantics(
                button: true,
                selected: v == value,
                child: Material(
                  color: v == value ? t.text : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: v == value ? t.text : t.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (v == value) return;
                      tapHaptic();
                      onChanged(v);
                    },
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 36),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 13),
                      child: Text(
                        label,
                        style: AppType.row.copyWith(
                          fontSize: 13.5,
                          color: v == value ? t.bg : t.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}
