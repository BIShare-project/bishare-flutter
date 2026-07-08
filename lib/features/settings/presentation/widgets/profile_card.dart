import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/identity/device_identity.dart';
import '../../../../core/ui/app_ui.dart';

/// A device profile hero card (avatar + name + rename affordance).
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.alias, required this.onTap});
  final String alias;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final identity = getIt<DeviceIdentity>();
    return AppCard(
      gradient: true,
      onTap: onTap,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          AppAvatar(
            icon: iconForDevice(identity.deviceType),
            size: 50,
            online: true,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alias,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'This device · tap to rename',
                  style: TextStyle(fontSize: 13, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          AppSvgIcon(AppIcons.renameEdit, size: 18, color: cs.mutedForeground),
        ],
      ),
    );
  }
}
