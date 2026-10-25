import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';

/// A transfer card: progress ring + percent, title/file, transport badge, live
/// speed + ETA, and cancel / retry affordances. Built on [AppCard].
class TransferCard extends StatelessWidget {
  const TransferCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.fraction,
    this.speed = 0,
    this.etaSeconds,
    this.onCancel,
    this.onRetry,
    this.isError = false,
    this.accentColor,
    this.transport = 'TCP',
  });

  final String icon;
  final String title;
  final String subtitle;
  final double fraction;
  final double speed;
  final double? etaSeconds;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final bool isError;
  final Color? accentColor;
  final String transport;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final pct = (fraction * 100).clamp(0, 100).toInt();
    final accent = isError ? cs.destructive : (accentColor ?? cs.primary);
    final t = context.tokens;
    // A solid floating card: no blur, no saveLayer (redesign-plan.md 1.3).
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: t.isDark ? 0.55 : 0.16),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isError ? accent : t.line),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                height: 46,
                child: isError
                    ? AppSvgIcon(icon, color: accent, size: 30)
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 46,
                            height: 46,
                            child: CircularProgressIndicator(
                              value: fraction == 0 ? null : fraction,
                              strokeWidth: 4,
                              backgroundColor: cs.muted,
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.foreground,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: cs.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.mutedForeground,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        AppBadge(transport),
                        if (!isError && speed > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${fmtSpeed(speed)}'
                            '${etaSeconds != null ? ' · ${fmtEta(etaSeconds!)}' : ''}',
                            style: TextStyle(
                              color: cs.mutedForeground,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onRetry != null)
                ShadButton.ghost(
                  onPressed: onRetry,
                  leading: const AppSvgIcon(AppIcons.refreshSync, size: 16),
                  child: Text('home.retry'.tr()),
                ),
              if (onCancel != null)
                ShadIconButton.ghost(
                  icon: const AppSvgIcon(AppIcons.close, size: 18),
                  onPressed: onCancel,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
