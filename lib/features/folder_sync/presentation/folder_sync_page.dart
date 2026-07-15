import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../discovery/data/discovery_service.dart';
import '../data/sync_engine.dart';
import 'folder_sync_cubit.dart';
import 'widgets/conflict_sheet.dart';
import 'widgets/pair_setup_sheet.dart';
import 'widgets/sync_pair_card.dart';

/// Folder Sync (Tahap 4 M1): the pair list + "new pair" flow. LAN one-way push,
/// manual trigger — watching/two-way arrive in M2, cloud fallback in M3.
class FolderSyncPage extends StatelessWidget {
  const FolderSyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => FolderSyncCubit(
        getIt<SyncEngine>(),
        getIt<AppDatabase>().syncDao,
        getIt<DiscoveryService>(),
      ),
      child: const _FolderSyncView(),
    );
  }
}

class _FolderSyncView extends StatelessWidget {
  const _FolderSyncView();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocConsumer<FolderSyncCubit, FolderSyncState>(
          listenWhen: (prev, curr) =>
              prev.errorKey != curr.errorKey && curr.errorKey != null,
          listener: (context, state) {
            toast(context, state.errorKey!.tr(), type: ToastType.error);
            context.read<FolderSyncCubit>().clearError();
          },
          builder: (context, state) {
            final cubit = context.read<FolderSyncCubit>();
            return AppResponsivePane(
              maxWidth: 640,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: 'sync.title'.tr(),
                    subtitle: 'sync.subtitle'.tr(),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: !state.loaded
                        ? const Center(child: CircularProgressIndicator())
                        : state.pairs.isEmpty
                            ? _empty(context)
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 8, 14, 90),
                                children: [
                                  for (final v in state.pairs)
                                    SyncPairCard(
                                      view: v,
                                      onSyncNow: () =>
                                          cubit.syncNow(v.pair.id),
                                      onTogglePause: () => cubit.setPaused(
                                        v.pair.id,
                                        !v.pair.paused,
                                      ),
                                      onDelete: () =>
                                          _confirmDelete(context, cubit, v),
                                      onConflicts: () =>
                                          showConflictSheet(context, cubit, v),
                                      onToggleCloud: () {
                                        final enabling =
                                            v.pair.mode != 'lanCloud';
                                        final tier = context
                                            .read<AuthCubit>()
                                            .state
                                            .tier;
                                        if (enabling &&
                                            tier != 'pro' &&
                                            tier != 'business') {
                                          toast(
                                            context,
                                            'sync.cloud_needs_pro'.tr(),
                                            type: ToastType.error,
                                          );
                                          return;
                                        }
                                        cubit.setCloud(v.pair.id, enabling);
                                      },
                                    ),
                                ],
                              ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: AppButton(
                      label: 'sync.new_pair'.tr(),
                      icon: AppIcons.newFolder,
                      fullWidth: true,
                      loading: state.busy,
                      onPressed: () => showPairSetupSheet(context, cubit),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: AppEmptyState(
          icon: AppIcons.refreshSync,
          title: 'sync.empty_title'.tr(),
          message: 'sync.empty_message'.tr(),
        ),
      );

  Future<void> _confirmDelete(
    BuildContext context,
    FolderSyncCubit cubit,
    SyncPairView v,
  ) async {
    await showAppSheet<void>(
      context,
      title: 'sync.delete_title'.tr(),
      subtitle: v.displayRoot,
      icon: AppIcons.trashDelete,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: Text(
              'sync.delete_message'.tr(),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: ShadTheme.of(sheetContext).colorScheme.mutedForeground,
              ),
            ),
          ),
          AppButton(
            label: 'common.delete'.tr(),
            variant: AppButtonVariant.destructive,
            fullWidth: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              cubit.deletePair(v.pair.id);
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'common.cancel'.tr(),
            variant: AppButtonVariant.ghost,
            fullWidth: true,
            onPressed: () => Navigator.of(sheetContext).pop(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
