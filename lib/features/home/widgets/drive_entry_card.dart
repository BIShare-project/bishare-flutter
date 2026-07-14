import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';

/// A prominent entry point to the cloud Drive (Fase B). Placed on the Home tab
/// so Drive stays one tap away without adding a sixth bottom-nav destination.
class DriveEntryCard extends StatelessWidget {
  const DriveEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppCard(
      gradient: true,
      onTap: () => context.push('/drive'),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AppSvgIcon(AppIcons.cloudSync, size: 24, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'drive.home_title'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'drive.home_subtitle'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          AppSvgIcon(
            AppIcons.chevronRight,
            size: 18,
            color: cs.mutedForeground.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}
