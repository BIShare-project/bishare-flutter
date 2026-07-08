import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/room_models.dart';

class RoomFileRow extends StatelessWidget {
  const RoomFileRow({
    super.key,
    required this.file,
    required this.isMine,
    required this.onDownload,
    required this.onOpen,
  });

  final RoomFile file;
  final bool isMine;
  final VoidCallback onDownload;

  /// Tap the row (thumbnail / name) to preview the file.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final thumb = file.thumbnailBytes;
    return GestureDetector(
      onTap: () {
        tapHaptic();
        onOpen();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.border.withValues(alpha: 0.7)),
        ),
        child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: thumb != null
                ? Image.memory(thumb, width: 44, height: 44, fit: BoxFit.cover)
                : Container(
                    width: 44,
                    height: 44,
                    color: cs.muted,
                    child: AppSvgIcon(
                      fileIcon(file.fileType),
                      color: cs.mutedForeground,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(file.size)} · ${file.ownerAlias}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          if (isMine)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AppSvgIcon(AppIcons.check, size: 20, color: kOnlineGreen),
            )
          else
            ShadIconButton.ghost(
              icon: const AppSvgIcon(AppIcons.downloadFile, size: 20),
              onPressed: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}
