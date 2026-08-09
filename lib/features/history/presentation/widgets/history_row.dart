import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../history_cubit.dart';

class HistoryRow extends StatelessWidget {
  const HistoryRow({super.key, required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final r = record;
    final sent = r.direction == 'sent';
    final dirLabel = sent
        ? 'history.to_alias'.tr(namedArgs: {'alias': r.deviceAlias})
        : 'history.from_alias'.tr(namedArgs: {'alias': r.deviceAlias});
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.destructive,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: AppSvgIcon(AppIcons.trashDelete, color: cs.destructiveForeground),
      ),
      onDismissed: (_) => context.read<HistoryCubit>().deleteEntry(r),
      child: AppRowMenu(
        title: r.fileName,
        subtitle: dirLabel,
        actions: _actions(context, r),
        child: AppListTile(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          leading: SizedBox(
            width: 38,
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                MediaThumb(path: r.savedPath, mime: r.fileType),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: cs.card,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.border.withValues(alpha: 0.8),
                      ),
                    ),
                    child: AppSvgIcon(
                      sent ? AppIcons.arrowUp : AppIcons.arrowDown,
                      size: 10,
                      color: cs.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ),
          title: Text(r.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'history.row_subtitle'.tr(
              namedArgs: {
                'dir': dirLabel,
                'size': formatBytes(r.fileSize),
                'time': _time(r.timestamp),
              },
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: r.encrypted
              ? const AppSvgIcon(
                  AppIcons.passwordLock,
                  size: 15,
                  color: kOnlineGreen,
                )
              : null,
          onTap: () => _open(context, r),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, TransferRecord r) async {
    final path = r.savedPath;
    if (path == null || !File(path).existsSync()) {
      toast(
        context,
        'history.file_not_stored'.tr(),
        type: ToastType.error,
      );
      return;
    }
    if (!await openFile(path) && context.mounted) {
      toast(context, 'common.no_app_open'.tr(), type: ToastType.error);
    }
  }

  List<AppMenuAction> _actions(BuildContext context, TransferRecord r) {
    final hasFile = r.savedPath != null && File(r.savedPath!).existsSync();
    return [
      if (hasFile)
        AppMenuAction(
          icon: AppIcons.externalLink,
          label: 'history.open'.tr(),
          onTap: () => _open(context, r),
        ),
      if (hasFile)
        AppMenuAction(
          icon: AppIcons.shareLink,
          label: 'history.share'.tr(),
          onTap: () => SharePlus.instance.share(
            ShareParams(files: [XFile(r.savedPath!)]),
          ),
        ),
      AppMenuAction(
        icon: AppIcons.trashDelete,
        label: 'history.delete'.tr(),
        destructive: true,
        onTap: () => context.read<HistoryCubit>().deleteEntry(r),
      ),
    ];
  }
}

String _time(DateTime t) {
  final now = DateTime.now();
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  String p(int v) => v.toString().padLeft(2, '0');
  return sameDay
      ? '${p(t.hour)}:${p(t.minute)}'
      : '${t.year}-${p(t.month)}-${p(t.day)}';
}
