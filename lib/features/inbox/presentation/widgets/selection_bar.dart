import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.total,
    required this.selected,
    required this.canSave,
    required this.onSelectAll,
    required this.onSave,
    required this.onDelete,
  });

  final int total;
  final int selected;
  final bool canSave;
  final VoidCallback onSelectAll;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final allSelected = selected == total && total > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Row(
        children: [
          Expanded(
            child: ShadButton.outline(
              onPressed: onSelectAll,
              child: Text(allSelected ? 'inbox.none'.tr() : 'inbox.all'.tr()),
            ),
          ),
          if (canSave) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ShadButton.outline(
                onPressed: selected == 0 ? null : onSave,
                leading: const AppSvgIcon(AppIcons.imageDown, size: 16),
                child: Text('inbox.save'.tr()),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: ShadButton.destructive(
              onPressed: selected == 0 ? null : onDelete,
              leading: const AppSvgIcon(AppIcons.trashDelete, size: 16),
              child: Text('inbox.delete'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}
