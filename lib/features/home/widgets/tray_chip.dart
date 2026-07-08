import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../../send/domain/sendable_file.dart';

class TrayChip extends StatelessWidget {
  const TrayChip({super.key, 
    required this.file,
    required this.onRemove,
    required this.onTap,
  });
  final SendableFile file;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final isImage = file.mimeType.startsWith('image/');
    return GestureDetector(
      onTap: () {
        tapHaptic();
        onTap();
      },
      child: Container(
        width: 138,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: cs.muted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: isImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(file.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            AppSvgIcon(AppIcons.image, color: cs.mutedForeground),
                      ),
                    )
                  : AppSvgIcon(
                      fileIcon(file.mimeType),
                      size: 22,
                      color: cs.mutedForeground,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: cs.foreground),
              ),
            ),
            GestureDetector(
              onTap: () {
                tapHaptic();
                onRemove();
              },
              child: AppSvgIcon(AppIcons.close, size: 16, color: cs.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
