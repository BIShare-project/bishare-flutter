import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../data/sync_engine.dart';
import '../folder_sync_cubit.dart';

/// One sync pair: folder name, peer presence, live phase, and the row actions
/// (sync now / pause / delete). Pure presentation — callbacks go to the cubit.
class SyncPairCard extends StatelessWidget {
  const SyncPairCard({
    super.key,
    required this.view,
    required this.onSyncNow,
    required this.onTogglePause,
    required this.onDelete,
    this.onConflicts,
    this.onToggleCloud,
  });

  final SyncPairView view;
  final VoidCallback onSyncNow;
  final VoidCallback onTogglePause;
  final VoidCallback onDelete;

  /// Opens the conflict-resolution sheet (shown when [SyncPairView.conflicts] > 0).
  final VoidCallback? onConflicts;

  /// Toggles the pair between LAN-only and LAN+Cloud (Pro).
  final VoidCallback? onToggleCloud;

  String get _folderName {
    final parts = view.displayRoot
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.isNotEmpty);
    return parts.isEmpty ? view.displayRoot : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final paused = view.pair.paused;
    final syncing = switch (view.phase) {
      SyncPhase.scanning || SyncPhase.exchanging || SyncPhase.pushing => true,
      _ => false,
    };

    return AppCard(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppSvgIcon(
                  AppIcons.refreshSync,
                  size: 21,
                  color: paused ? cs.mutedForeground : cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _folderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: cs.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      view.displayRoot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(context),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: syncing
                      ? 'sync.phase_${view.phase.name}'.tr()
                      : 'sync.sync_now'.tr(),
                  icon: AppIcons.refreshSync,
                  size: AppButtonSize.small,
                  fullWidth: true,
                  loading: syncing,
                  disabled: paused || !view.peerOnline,
                  onPressed: onSyncNow,
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: view.pair.mode == 'lanCloud'
                    ? 'sync.cloud_on'.tr()
                    : 'sync.cloud_off'.tr(),
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
                onPressed: onToggleCloud,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: paused ? 'sync.resume'.tr() : 'sync.pause'.tr(),
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
                onPressed: onTogglePause,
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'common.delete'.tr(),
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.small,
                onPressed: onDelete,
              ),
            ],
          ),
          if (view.conflicts > 0) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'sync.conflicts_button'
                  .tr(namedArgs: {'count': '${view.conflicts}'}),
              icon: AppIcons.circleAlert,
              variant: AppButtonVariant.outline,
              size: AppButtonSize.small,
              fullWidth: true,
              onPressed: onConflicts,
            ),
          ],
          if (view.errorMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSvgIcon(AppIcons.circleAlert, size: 14, color: cs.destructive),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    view.errorMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: cs.destructive),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    if (view.pair.paused) {
      return AppBadge('sync.paused'.tr(), color: cs.mutedForeground);
    }
    if (!view.peerOnline) {
      // With the cloud fallback on, an away peer still syncs — say so instead
      // of the alarming "offline".
      return view.pair.mode == 'lanCloud'
          ? AppBadge('sync.via_cloud'.tr())
          : AppBadge('sync.peer_offline'.tr(), color: cs.mutedForeground);
    }
    return switch (view.phase) {
      SyncPhase.error => AppBadge('sync.failed'.tr(), color: cs.destructive),
      SyncPhase.pushing =>
        AppBadge('${view.pushedFiles}/${view.totalFiles}'),
      SyncPhase.scanning || SyncPhase.exchanging =>
        AppBadge('sync.working'.tr()),
      SyncPhase.done => AppBadge('sync.up_to_date'.tr()),
      // Idle: a pair that has ever completed a sync (either direction — the
      // receiver stamps lastSyncAt too) is up to date, not merely "ready".
      _ => view.pair.lastSyncAt != null
          ? AppBadge('sync.up_to_date'.tr())
          : AppBadge('sync.ready'.tr()),
    };
  }
}
