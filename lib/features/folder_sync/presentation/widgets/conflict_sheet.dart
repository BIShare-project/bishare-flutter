import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/sync_engine.dart';
import '../folder_sync_cubit.dart';

/// The §6.1 conflict-resolution sheet: every unresolved conflict for a pair,
/// each with keep-mine / keep-theirs / keep-both. Nothing here can lose data —
/// discarded versions go to the sync-trash, "keep both" renames the copy into
/// a syncable name.
Future<void> showConflictSheet(
  BuildContext context,
  FolderSyncCubit cubit,
  SyncPairView view,
) {
  return showAppSheet<void>(
    context,
    title: 'sync.conflicts_title'.tr(),
    subtitle: view.displayRoot,
    icon: AppIcons.circleAlert,
    builder: (sheetContext) => _ConflictList(cubit: cubit, pairId: view.pair.id),
  );
}

class _ConflictList extends StatefulWidget {
  const _ConflictList({required this.cubit, required this.pairId});

  final FolderSyncCubit cubit;
  final String pairId;

  @override
  State<_ConflictList> createState() => _ConflictListState();
}

class _ConflictListState extends State<_ConflictList> {
  List<SyncConflict>? _conflicts;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await widget.cubit.conflictsFor(widget.pairId);
    if (mounted) setState(() => _conflicts = rows);
  }

  Future<void> _resolve(SyncConflict c, ConflictChoice choice) async {
    setState(() => _busy.add(c.id));
    await widget.cubit.resolveConflict(c.id, choice);
    if (!mounted) return;
    _busy.remove(c.id);
    await _reload();
    if (mounted && (_conflicts?.isEmpty ?? false)) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final conflicts = _conflicts;
    if (conflicts == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (conflicts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppEmptyState(
          icon: AppIcons.verifiedCheck,
          title: 'sync.conflicts_empty_title'.tr(),
          message: 'sync.conflicts_empty_message'.tr(),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in conflicts) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: cs.muted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'sync.conflicts_explain'.tr(),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: cs.mutedForeground,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'sync.keep_mine'.tr(),
                        size: AppButtonSize.small,
                        variant: AppButtonVariant.outline,
                        fullWidth: true,
                        loading: _busy.contains(c.id),
                        onPressed: () =>
                            _resolve(c, ConflictChoice.keepMine),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'sync.keep_theirs'.tr(),
                        size: AppButtonSize.small,
                        variant: AppButtonVariant.outline,
                        fullWidth: true,
                        loading: _busy.contains(c.id),
                        onPressed: () =>
                            _resolve(c, ConflictChoice.keepTheirs),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'sync.keep_both'.tr(),
                        size: AppButtonSize.small,
                        fullWidth: true,
                        loading: _busy.contains(c.id),
                        onPressed: () => _resolve(c, ConflictChoice.keepBoth),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}
