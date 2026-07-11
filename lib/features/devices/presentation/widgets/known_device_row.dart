import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/devices/device_registry.dart';
import '../../../../core/ui/app_ui.dart';
import 'device_detail_sheet.dart';
import 'last_seen.dart';

/// One roster row on the Devices dashboard: avatar with a live presence dot,
/// display name (+ favorite star), model + presence subtitle. Tap opens the
/// device detail sheet.
class KnownDeviceRow extends StatelessWidget {
  const KnownDeviceRow({super.key, required this.device});
  final KnownDeviceView device;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppListTile(
      onTap: () => showDeviceDetailSheet(context, device),
      leading: AppAvatar(
        icon: iconForDevice(device.deviceType ?? 'mobile'),
        size: 40,
        online: device.isOnline,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              device.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (device.isFavorite) ...[
            const SizedBox(width: 6),
            const AppSvgIcon(AppIcons.starFavorite, size: 13, color: kAmber),
          ],
        ],
      ),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AppSvgIcon(
        AppIcons.chevronRight,
        size: 18,
        color: cs.mutedForeground.withValues(alpha: 0.6),
      ),
    );
  }

  String _subtitle() {
    final presence = device.isOnline
        ? 'devices.online'.tr()
        : 'devices.last_seen'.tr(
            namedArgs: {'when': relativeLastSeen(device.lastSeen)},
          );
    final model = device.deviceModel;
    return (model == null || model.isEmpty) ? presence : '$model · $presence';
  }
}
