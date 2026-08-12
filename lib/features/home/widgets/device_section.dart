import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../discovery/presentation/discovery_cubit.dart';
import '../../web_nearby/presentation/web_nearby_cubit.dart';
import 'browser_device_row.dart';
import 'device_grid.dart';
import 'device_row.dart';
import 'invite_device_sheet.dart';

class DeviceSection extends StatelessWidget {
  const DeviceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoveryCubit, List<DiscoveredDevice>>(
      builder: (context, devices) {
        return BlocBuilder<WebNearbyCubit, WebNearbyState>(
          builder: (context, web) {
            final browsers = web.peers;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The header (with the Devices dashboard entry) stays visible
                // even while nothing is discovered — known devices persist
                // over there.
                AppSectionHeader(
                  'home.nearby_devices'.tr(),
                  trailing: const _SeeAllDevicesLink(),
                ),
                if (devices.isEmpty && browsers.isEmpty) ...[
                  AppEmptyState(
                    icon: AppIcons.wifi,
                    title: 'home.looking_for_devices'.tr(),
                    message: 'home.no_devices_message'.tr(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Center(
                      child: ShadButton.outline(
                        onPressed: () => showInviteDeviceSheet(context),
                        leading: const AppSvgIcon(AppIcons.qrShare, size: 16),
                        child: Text('home.invite_device'.tr()),
                      ),
                    ),
                  ),
                ] else ...[
                  if (devices.isNotEmpty)
                    if (context.isWideLayout)
                      DeviceGrid(devices: devices)
                    else
                      AppGroup(
                        child: Column(
                          children: [
                            for (var i = 0; i < devices.length; i++) ...[
                              if (i > 0) const AppRowDivider(),
                              DeviceRow(device: devices[i]),
                            ],
                          ],
                        ),
                      ),
                  // Browsers on this network (bishare.app/transfer → Nearby):
                  // same tap-to-send flow, bytes go over WebRTC.
                  if (browsers.isNotEmpty) ...[
                    if (devices.isNotEmpty) const SizedBox(height: 10),
                    AppGroup(
                      child: Column(
                        children: [
                          for (var i = 0; i < browsers.length; i++) ...[
                            if (i > 0) const AppRowDivider(),
                            BrowserDeviceRow(
                              peer: browsers[i],
                              sending:
                                  web.sendingTo.contains(browsers[i].peerId),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// "See all devices" — opens the Devices dashboard (full roster + last-seen).
class _SeeAllDevicesLink extends StatelessWidget {
  const _SeeAllDevicesLink();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          context.push('/devices');
        },
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('devices.see_all'.tr()),
            const SizedBox(width: 2),
            AppSvgIcon(
              AppIcons.chevronRight,
              size: 12,
              color: cs.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
