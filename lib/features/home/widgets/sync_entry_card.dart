import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';

/// Home entry to Folder Sync (Tahap 4) — the same compact pattern as
/// [DriveEntryCard], one tap to the pair list.
class SyncEntryCard extends StatelessWidget {
  const SyncEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppCard(
      onTap: () => context.push('/folder-sync'),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                AppSvgIcon(AppIcons.refreshSync, size: 24, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'sync.home_title'.tr(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'sync.home_subtitle'.tr(),
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
