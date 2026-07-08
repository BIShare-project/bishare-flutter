import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';

class AddFilesBar extends StatelessWidget {
  const AddFilesBar({super.key, required this.onPicked});
  final ValueChanged<List<String>> onPicked;

  Future<void> _pick(bool mediaOnly) async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: mediaOnly ? FileType.media : FileType.any,
    );
    final paths = res?.paths.whereType<String>().toList() ?? const [];
    if (paths.isNotEmpty) onPicked(paths);
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: PillButton(
            icon: AppIcons.image,
            label: 'room.photos'.tr(),
            color: cs.primary,
            onTap: () => _pick(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: PillButton(
            icon: AppIcons.folder,
            label: 'room.files'.tr(),
            color: const Color(0xFFEA580C),
            onTap: () => _pick(false),
          ),
        ),
      ],
    );
  }
}

class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        tapHaptic();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppSvgIcon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
