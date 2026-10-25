import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';
import 'app_svg_icon.dart';

/// One action on an [AppSelectionBar] (an icon over a short label).
class AppBarAction {
  const AppBarAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
}

/// The floating bar that appears while something is selected, the same on
/// every screen (Kirim, Kotak Masuk, Drive): clear on the leading side, the
/// [summary] in the middle, then either [actions] or one [primary] button.
/// It carries the BIShare gradient ("sending") and slides in with a
/// transform, so showing it never relayouts the screen.
class AppSelectionBar extends StatelessWidget {
  const AppSelectionBar({
    super.key,
    required this.visible,
    required this.onClear,
    required this.summary,
    this.onSummaryTap,
    this.actions = const [],
    this.primary,
  });

  final bool visible;
  final VoidCallback onClear;

  /// What is selected (thumbnails, a count and a size).
  final Widget summary;
  final VoidCallback? onSummaryTap;
  final List<AppBarAction> actions;

  /// One white button at the end ("Kirim"). Wins over [actions].
  final (String label, VoidCallback onTap)? primary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.6),
        duration: reduce ? Duration.zero : AppMotion.bar,
        curve: AppMotion.enter,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: t.brandSurface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(2, 6, 6, 6),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: Row(
                      children: [
                        _BarButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).clearButtonTooltip,
                          onTap: onClear,
                          child: const AppSvgIcon(
                            AppIcons.close,
                            size: 22,
                            color: Colors.white,
                          ),
                        ),
                        Expanded(
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: onSummaryTap,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: summary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (primary != null)
                          _PrimaryButton(label: primary!.$1, onTap: primary!.$2)
                        else
                          for (final a in actions)
                            _BarButton(
                              tooltip: a.label,
                              onTap: a.enabled ? a.onTap : null,
                              wide: true,
                              child: Opacity(
                                opacity: a.enabled ? 1 : 0.45,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppSvgIcon(
                                      a.icon,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      a.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.nav.copyWith(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
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
        ),
      ),
    );
  }
}

/// A count over a size ("3 item" over "11,1 MB"): the usual [AppSelectionBar.summary], with up to
/// three stacked [thumbs] before it.
class AppSelectionSummary extends StatelessWidget {
  const AppSelectionSummary({
    super.key,
    required this.title,
    this.subtitle,
    this.thumbs = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> thumbs;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (thumbs.isNotEmpty) ...[
          const SizedBox(width: 2),
          SizedBox(
            width: 30.0 + 18 * (thumbs.length.clamp(1, 3) - 1),
            height: 30,
            child: Stack(
              children: [
                for (var i = 0; i < thumbs.length && i < 3; i++)
                  PositionedDirectional(
                    start: 18.0 * i,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1.5,
                        ),
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: thumbs[i],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowStrong.copyWith(
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.small.copyWith(
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.wide = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic();
                  onTap!();
                },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: wide ? 56 : 44,
              minHeight: 48,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: AppType.rowStrong.copyWith(
                  // The deep end of the gradient reads on white (7:1).
                  color: t.isDark
                      ? const Color(0xFF1D4ED8)
                      : const Color(0xFF0B4FB8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
