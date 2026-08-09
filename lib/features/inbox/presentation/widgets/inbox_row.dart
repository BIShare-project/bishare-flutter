import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../instant_share/presentation/instant_share_sheet.dart';
import '../inbox_cubit.dart';

class InboxRow extends StatelessWidget {
  const InboxRow({
    super.key,
    required this.record,
    required this.selecting,
    required this.selected,
    required this.onToggle,
  });

  final TransferRecord record;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;

  bool _isImage(String? m) => m?.startsWith('image/') ?? false;
  bool _isMedia(String? m) =>
      (m?.startsWith('image/') ?? false) || (m?.startsWith('video/') ?? false);

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final r = record;
    final tile = AppListTile(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      leading: selecting
          ? AppSvgIcon(
              selected ? AppIcons.successSent : AppIcons.circle,
              size: 26,
              color: selected ? cs.primary : cs.mutedForeground,
            )
          : MediaThumb(path: r.savedPath, mime: r.fileType),
      title: Text(r.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'inbox.row_meta'.tr(
          namedArgs: {
            'alias': r.deviceAlias,
            'size': formatBytes(r.fileSize),
            'time': _time(r.timestamp),
          },
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: r.encrypted
          ? const AppSvgIcon(AppIcons.passwordLock, size: 15, color: kOnlineGreen)
          : null,
      onTap: () {
        if (selecting) {
          onToggle();
        } else {
          _openRow(context, r);
        }
      },
    );
    final content = selecting
        ? tile
        : AppRowMenu(
            title: r.fileName,
            subtitle: 'inbox.from'.tr(namedArgs: {'alias': r.deviceAlias}),
            actions: _actions(context, r),
            child: tile,
          );
    if (selecting && selected) {
      return ColoredBox(
        color: cs.primary.withValues(alpha: 0.08),
        child: content,
      );
    }
    return content;
  }

  List<AppMenuAction> _actions(BuildContext context, TransferRecord r) {
    final hasFile = r.savedPath != null && File(r.savedPath!).existsSync();
    return [
      if (hasFile)
        AppMenuAction(
          icon: AppIcons.externalLink,
          label: 'inbox.open'.tr(),
          onTap: () => _openRow(context, r),
        ),
      if (hasFile)
        AppMenuAction(
          icon: AppIcons.shareLink,
          label: 'inbox.share'.tr(),
          onTap: () => SharePlus.instance.share(
            ShareParams(files: [XFile(r.savedPath!)]),
          ),
        ),
      if (hasFile)
        AppMenuAction(
          icon: AppIcons.qrShare,
          label: 'inbox.share_via_qr'.tr(),
          onTap: () => showInstantShare(
            context,
            path: r.savedPath!,
            fileName: r.fileName,
            mimeType: r.fileType ?? 'application/octet-stream',
          ),
        ),
      if (hasFile && InboxCubit.canSaveToPhotos && _isMedia(r.fileType))
        AppMenuAction(
          icon: AppIcons.imageDown,
          label: 'inbox.save_to_photos'.tr(),
          onTap: () async {
            final ok = await context.read<InboxCubit>().saveToPhotos(r);
            if (context.mounted) {
              toast(
                context,
                ok ? 'inbox.saved_to_photos'.tr() : 'inbox.could_not_save'.tr(),
                type: ok ? ToastType.success : ToastType.error,
              );
            }
          },
        ),
      AppMenuAction(
        icon: AppIcons.trashDelete,
        label: 'inbox.delete'.tr(),
        destructive: true,
        onTap: () => context.read<InboxCubit>().deleteEntry(r),
      ),
    ];
  }

  void _openRow(BuildContext context, TransferRecord r) {
    // Images open the swipeable gallery; other files open externally.
    final items = context.read<InboxCubit>().state;
    if (_isImage(r.fileType)) {
      final imgs = items.where((x) => _isImage(x.fileType)).toList();
      final start = imgs.indexWhere((x) => x.id == r.id);
      context.push(
        '/gallery',
        extra: (images: imgs, startIndex: start < 0 ? 0 : start),
      );
      return;
    }
    _openExternal(context, r);
  }

  Future<void> _openExternal(BuildContext context, TransferRecord r) async {
    final path = r.savedPath;
    if (path == null || !File(path).existsSync()) {
      toast(
        context,
        'inbox.not_stored'.tr(),
        type: ToastType.error,
      );
      return;
    }
    if (!await openFile(path) && context.mounted) {
      toast(context, 'common.no_app_open'.tr(), type: ToastType.error);
    }
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
