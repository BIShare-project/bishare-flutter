import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/managed_file.dart';

class FileRow extends StatelessWidget {
  const FileRow({
    super.key,
    required this.file,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final ManagedFile file;
  final ValueChanged<ManagedFile> onOpen;
  final ValueChanged<ManagedFile> onShare;
  final Future<void> Function(ManagedFile) onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final f = file;
    return Dismissible(
      key: ValueKey(f.path),
      direction: DismissDirection.endToStart,
      background: Container(
        color: cs.destructive,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        child: AppSvgIcon(AppIcons.trashDelete, color: cs.destructiveForeground),
      ),
      onDismissed: (_) => onDelete(f),
      child: AppRowMenu(
        title: f.name,
        subtitle: '${f.category} · ${formatBytes(f.size)}',
        actions: [
          AppMenuAction(
            icon: AppIcons.externalLink,
            label: 'common.open'.tr(),
            onTap: () => onOpen(f),
          ),
          AppMenuAction(
            icon: AppIcons.shareLink,
            label: 'common.share'.tr(),
            onTap: () => onShare(f),
          ),
          AppMenuAction(
            icon: AppIcons.trashDelete,
            label: 'common.delete'.tr(),
            destructive: true,
            onTap: () => onDelete(f),
          ),
        ],
        child: AppListTile(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          leading: MediaThumb(path: f.path, mime: f.fileType),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${f.category} · ${formatBytes(f.size)} · ${f.sender}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: f.encrypted
              ? const AppSvgIcon(
                  AppIcons.passwordLock,
                  size: 15,
                  color: kOnlineGreen,
                )
              : null,
          onTap: () => onOpen(f),
        ),
      ),
    );
  }
}
