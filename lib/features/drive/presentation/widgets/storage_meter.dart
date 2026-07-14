import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/drive_models.dart';

/// A compact storage-quota card: a used/limit bar, the percentage, and the tier
/// badge — styled to match the app's [AppCard] hero surfaces.
class StorageMeter extends StatelessWidget {
  const StorageMeter({super.key, required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final fraction = usage.fraction;
    // Warn (amber) past 80%, danger (red) past 95%.
    final barColor = fraction >= 0.95
        ? cs.destructive
        : fraction >= 0.8
        ? kAmber
        : cs.primary;
    return AppCard(
      gradient: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon(AppIcons.storageUsage, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'drive.storage'.tr(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.foreground,
                ),
              ),
              const Spacer(),
              if (usage.tier.isNotEmpty) AppBadge(usage.tier.toUpperCase()),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: cs.muted,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'drive.storage_used'.tr(
              namedArgs: {
                'used': formatBytes(usage.used),
                'limit': formatBytes(usage.limit),
                'percent': usage.usedPercent.toStringAsFixed(0),
              },
            ),
            style: TextStyle(fontSize: 12.5, color: cs.mutedForeground),
          ),
        ],
      ),
    );
  }
}
