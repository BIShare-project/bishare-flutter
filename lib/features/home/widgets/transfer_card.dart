import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';

/// A transfer card: progress ring + percent, title/file, transport badge, live
/// speed + ETA, and cancel / retry affordances. Built on [AppCard].
class TransferCard extends StatelessWidget {
  const TransferCard({super.key, 
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = (isDark ? cs.card : cs.background).withValues(alpha: 0.82);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          // saveLayer stops the BackdropFilter blur from bleeding past the
          // rounded corners (visible as clipped corners in dark mode).
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surface,
                // Match the clip radius so the border follows the rounded
                // corners instead of being cut square by the ClipRRect.
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
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
        ),
      ),
    );
  }
}
