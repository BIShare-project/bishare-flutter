import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../clipboard_cubit.dart';

/// One synced clipboard item: an image thumbnail (via [MediaThumb]) or a text
/// snippet, with copy-again on tap and a long-press/right-click menu
/// (copy / save-to-files / delete). Swipe-to-delete like History rows.
class ClipboardHistoryRow extends StatelessWidget {
  const ClipboardHistoryRow({
    super.key,
    required this.entry,
    required this.selfFingerprint,
  });

  final ClipboardHistoryData entry;

  /// Our own fingerprint — entries we broadcast show "You" as the source.
  final String selfFingerprint;

  bool get _isImage => entry.kind == 'image';

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final title = _isImage
        ? (entry.fileName ?? 'clipboard.image_label'.tr())
        : (entry.textContent ?? '').replaceAll('\n', ' ');
    final from = entry.senderFingerprint == selfFingerprint
        ? 'clipboard.you'.tr()
        : entry.senderAlias;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.destructive,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: AppSvgIcon(AppIcons.trashDelete, color: cs.destructiveForeground),
      ),
      onDismissed: (_) => context.read<ClipboardCubit>().remove(entry),
      child: AppRowMenu(
        title: title,
        subtitle: from,
        actions: _actions(context),
        child: AppListTile(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          leading: MediaThumb(
            path: _isImage ? (entry.filePath ?? entry.previewPath) : null,
            mime: _isImage ? entry.mime : 'text/plain',
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'clipboard.row_subtitle'.tr(
              namedArgs: {'from': from, 'time': _time(entry.createdAt)},
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _copy(context),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final ok = await context.read<ClipboardCubit>().copyAgain(entry);
    if (!context.mounted) return;
    if (ok) {
      toast(context, 'clipboard.copied'.tr());
    } else {
      toast(context, 'clipboard.copy_failed'.tr(), type: ToastType.error);
    }
  }

  Future<void> _save(BuildContext context) async {
    final path = await context.read<ClipboardCubit>().saveToFiles(entry);
    if (!context.mounted) return;
    if (path != null) {
      toast(context, 'clipboard.saved'.tr());
    } else {
      toast(context, 'clipboard.save_failed'.tr(), type: ToastType.error);
    }
  }

  List<AppMenuAction> _actions(BuildContext context) {
    final hasFile =
        entry.filePath != null && File(entry.filePath!).existsSync();
    return [
      AppMenuAction(
        icon: AppIcons.copyDuplicate,
        label: 'common.copy'.tr(),
        onTap: () => _copy(context),
      ),
      if (_isImage && hasFile)
        AppMenuAction(
          icon: AppIcons.downloadFile,
          label: 'clipboard.save'.tr(),
          onTap: () => _save(context),
        ),
      AppMenuAction(
        icon: AppIcons.trashDelete,
        label: 'common.delete'.tr(),
        destructive: true,
        onTap: () => context.read<ClipboardCubit>().remove(entry),
      ),
    ];
  }

  static String _time(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    String p(int v) => v.toString().padLeft(2, '0');
    return sameDay
        ? '${p(t.hour)}:${p(t.minute)}'
        : '${t.year}-${p(t.month)}-${p(t.day)}';
  }
}
