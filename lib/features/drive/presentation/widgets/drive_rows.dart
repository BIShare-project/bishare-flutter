import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/drive_models.dart';

/// The date portion of an ISO-8601 timestamp (e.g. "2026-07-11"), or "".
String _isoDate(String iso) => iso.contains('T') ? iso.split('T').first : iso;

Widget _chevron(ShadColorScheme cs) => AppSvgIcon(
  AppIcons.chevronRight,
  size: 18,
  color: cs.mutedForeground.withValues(alpha: 0.6),
);

/// A folder row: tap to open; long-press / right-click for actions.
class DriveFolderRow extends StatelessWidget {
  const DriveFolderRow({
    super.key,
    required this.folder,
    required this.onOpen,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final DriveFolder folder;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppRowMenu(
      title: folder.name,
      subtitle: 'drive.folder'.tr(),
      actions: [
        AppMenuAction(
          icon: AppIcons.renameEdit,
          label: 'drive.rename'.tr(),
          onTap: onRename,
        ),
        AppMenuAction(
          icon: AppIcons.moveFile,
          label: 'drive.move'.tr(),
          onTap: onMove,
        ),
        AppMenuAction(
          icon: AppIcons.shareLink,
          label: 'drive.share'.tr(),
          onTap: onShare,
        ),
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'common.delete'.tr(),
          destructive: true,
          onTap: onDelete,
        ),
      ],
      child: AppListTile(
        leading: AppSvgIcon(AppIcons.folder, size: 34, color: cs.primary),
        title: Text(
          folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('drive.folder'.tr()),
        trailing: _chevron(cs),
        onTap: onOpen,
      ),
    );
  }
}

/// A file row: tap to download; long-press / right-click for actions.
class DriveFileRow extends StatelessWidget {
  const DriveFileRow({
    super.key,
    required this.file,
    required this.onTap,
    required this.onDownload,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final DriveFile file;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = _isoDate(file.createdAt);
    final subtitle = date.isEmpty
        ? formatBytes(file.size)
        : '${formatBytes(file.size)}  ·  $date';
    return AppRowMenu(
      title: file.name,
      subtitle: subtitle,
      actions: [
        AppMenuAction(
          icon: AppIcons.downloadFile,
          label: 'common.download'.tr(),
          onTap: onDownload,
        ),
        AppMenuAction(
          icon: AppIcons.shareLink,
          label: 'drive.share'.tr(),
          onTap: onShare,
        ),
        AppMenuAction(
          icon: AppIcons.renameEdit,
          label: 'drive.rename'.tr(),
          onTap: onRename,
        ),
        AppMenuAction(
          icon: AppIcons.moveFile,
          label: 'drive.move'.tr(),
          onTap: onMove,
        ),
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'common.delete'.tr(),
          destructive: true,
          onTap: onDelete,
        ),
      ],
      child: AppListTile(
        leading: MediaThumb(path: null, mime: file.mimeType),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        onTap: onTap,
      ),
    );
  }
}
