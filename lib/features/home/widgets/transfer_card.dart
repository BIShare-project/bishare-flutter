import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/ui/app_ui.dart';

/// The floating card of a live or just-finished transfer (redesign-plan.md
/// 4.2), one look for sending and receiving: a round glyph, what is moving and
/// how far, an optional text action ("View", "Retry") and a close or cancel
/// button. While bytes move, a thin line shows the progress. A solid card: no
/// blur, no saveLayer, no looping animation.
class TransferCard extends StatelessWidget {
  const TransferCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.fraction,
    this.tone,
    this.filled = false,
    this.badge,
    this.action,
    this.onClose,
    this.closeTooltip,
  });

  final String icon;
  final String title;
  final String subtitle;

  /// 0 to 1 while bytes move; null when there is nothing to show (done, error).
  final double? fraction;

  /// The glyph and progress colour; the send accent by default.
  final Color? tone;

  /// Draws the glyph on a solid [tone] disc (done) instead of a soft one.
  final bool filled;

  /// A small label after the subtitle (the transport: TCP, QUIC).
  final String? badge;
  final (String label, VoidCallback onTap)? action;
  final VoidCallback? onClose;
  final String? closeTooltip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = tone ?? t.accent;
    final f = fraction;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 6, 12),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.14),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? c
                        : c.withValues(alpha: t.isDark ? 0.18 : 0.12),
                  ),
                  child: AppSvgIcon(
                    icon,
                    size: 21,
                    color: filled ? AppPalette.onColor(c) : c,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowStrong.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.small.copyWith(color: t.text2),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            AppBadge(badge!),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (action != null)
                  AppButton(
                    label: action!.$1,
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    onPressed: action!.$2,
                  ),
                if (onClose != null)
                  AppIconButton(
                    icon: AppIcons.close,
                    color: t.text2,
                    tooltip:
                        closeTooltip ??
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: onClose!,
                  ),
                if (action == null && onClose == null) const SizedBox(width: 6),
              ],
            ),
            if (f != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 2, end: 6),
                child: _Line(fraction: f, color: c, track: t.line),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 3 px progress line. Only its fill width changes, so a tick repaints one
/// small box.
class _Line extends StatelessWidget {
  const _Line({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: ColoredBox(
          color: track,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              heightFactor: 1,
              child: ColoredBox(color: color),
            ),
          ),
        ),
      ),
    );
  }
}
