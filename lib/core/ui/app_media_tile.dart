import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_format.dart';
import 'app_svg_icon.dart';

/// One square in a photo or video grid, the same in Send, Inbox and
/// Drive. Selected, the picture shrinks into an accent frame and carries its
/// send order. The picture is scaled with a transform, so selecting repaints
/// this tile only and never relayouts the grid.
class AppMediaTile extends StatelessWidget {
  const AppMediaTile({
    super.key,
    required this.image,
    required this.semanticLabel,
    this.selected = false,
    this.order,
    this.selectable = true,
    this.durationSeconds,
    this.sizeLabel,
    this.badge,
    this.onTap,
    this.onLongPress,
  });

  /// The thumbnail, already sized for the tile (decoded at display size).
  final Widget image;
  final String semanticLabel;
  final bool selected;

  /// 1-based position in the selection, shown in the check circle.
  final int? order;

  /// Shows the empty check circle when not selected.
  final bool selectable;

  /// A video's length: shown with a play mark at the bottom-start.
  final int? durationSeconds;

  /// A video's size at the bottom-end.
  final String? sizeLabel;

  /// A status mark in the bottom-end corner (the Drive backup state).
  final Widget? badge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static String _clock(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.disableAnimationsOf(context);
    const shadow = [Shadow(color: Color(0x99000000), blurRadius: 3)];
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                tapHaptic();
                onTap!();
              },
        onLongPress: onLongPress,
        child: ColoredBox(
          color: selected ? t.accentSoft : t.sunken,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedScale(
                scale: selected ? 0.84 : 1,
                duration: reduce ? Duration.zero : AppMotion.select,
                curve: AppMotion.standard,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(selected ? 10 : 0),
                  child: image,
                ),
              ),
              if (durationSeconds != null)
                PositionedDirectional(
                  start: 6,
                  bottom: 5,
                  child: Row(
                    children: [
                      const AppSvgIcon(
                        AppIcons.play,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _clock(durationSeconds!),
                        style: AppType.small.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          shadows: shadow,
                        ),
                      ),
                    ],
                  ),
                ),
              if (sizeLabel != null && badge == null)
                PositionedDirectional(
                  end: 6,
                  bottom: 5,
                  child: Text(
                    sizeLabel!,
                    style: AppType.small.copyWith(
                      color: Colors.white,
                      fontSize: 11.5,
                      shadows: shadow,
                    ),
                  ),
                ),
              if (badge != null)
                PositionedDirectional(end: 5, bottom: 5, child: badge!),
              if (selectable || selected)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: _Check(selected: selected, order: order),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected, this.order});

  final bool selected;
  final int? order;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accentStrong : const Color(0x24000000),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.95),
          width: 1.6,
        ),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 3)],
      ),
      child: selected
          ? (order == null
                ? AppSvgIcon(AppIcons.check, size: 14, color: t.onAccent)
                : Text(
                    '$order',
                    style: AppType.small.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.onAccent,
                    ),
                  ))
          : null,
    );
  }
}

/// A round check for list rows (the same circle as [AppMediaTile]'s).
class AppRowCheck extends StatelessWidget {
  const AppRowCheck({super.key, required this.selected, this.order});

  final bool selected;
  final int? order;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accentStrong : null,
        border: Border.all(
          color: selected ? t.accentStrong : t.text3,
          width: 1.6,
        ),
      ),
      child: selected
          ? (order == null
                ? AppSvgIcon(AppIcons.check, size: 14, color: t.onAccent)
                : Text(
                    '$order',
                    style: AppType.small.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.onAccent,
                    ),
                  ))
          : null,
    );
  }
}
