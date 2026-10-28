import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/room_models.dart';

/// A shared file of the room, a flat row like the Inbox's: its picture or
/// kind, name, size and who shared it; Download, or a check on one's own.
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

  /// Tap the row to preview the file.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final thumb = file.thumbnailBytes;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          onOpen();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: thumb != null
                      ? Image.memory(
                          thumb,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          color: t.sunken,
                          child: AppSvgIcon(
                            fileIcon(file.fileType),
                            size: 22,
                            color: t.text2,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Encrypted and not opened yet: the wire name is a
                        // placeholder.
                        file.isSealed
                            ? 'room.encrypted_file'.tr()
                            : file.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.row.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatBytes(file.size)} · ${file.ownerAlias}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
                if (isMine)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Semantics(
                      label: 'room.yours'.tr(),
                      child: AppSvgIcon(AppIcons.check, size: 20, color: t.ok),
                    ),
                  )
                else
                  AppIconButton(
                    icon: AppIcons.downloadFile,
                    tooltip: 'vault.download'.tr(),
                    onPressed: onDownload,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
