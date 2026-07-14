import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../domain/drive_models.dart';

/// A horizontally-scrolling folder path ("Drive / Photos / 2026"). Each segment
/// is tappable to jump up the tree; [onTap] receives the target folder id (null
/// for the Drive root).
class DriveBreadcrumb extends StatelessWidget {
  const DriveBreadcrumb({
    super.key,
    required this.trail,
    required this.onTap,
  });

  /// Root-first ancestor chain (current folder last).
  final List<DriveFolder> trail;
  final ValueChanged<String?> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 34,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            _segment(
              context,
              label: 'drive.title'.tr(),
              active: trail.isEmpty,
              onTap: () => onTap(null),
            ),
            for (var i = 0; i < trail.length; i++) ...[
              AppSvgIcon(
                AppIcons.chevronRight,
                size: 14,
                color: cs.mutedForeground.withValues(alpha: 0.5),
              ),
              _segment(
                context,
                label: trail[i].name,
                active: i == trail.length - 1,
                onTap: () => onTap(trail[i].id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final cs = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tapHaptic();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? cs.foreground : cs.mutedForeground,
          ),
        ),
      ),
    );
  }
}
