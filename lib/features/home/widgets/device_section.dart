import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../discovery/presentation/discovery_cubit.dart';
import '../../send/presentation/tray_cubit.dart';
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
                  const _OtherWays(),
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
                              sending: web.sendingTo.contains(
                                browsers[i].peerId,
                              ),
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

/// Shown while no device is found: the two ways that work without another
/// BIShare app on this network — a link that opens anywhere, and a browser on
/// the same Wi-Fi (bishare.app/transfer appears in the list above).
class _OtherWays extends StatelessWidget {
  const _OtherWays();

  static const _browserUrl = 'https://bishare.app/transfer';

  void _sendAsLink(BuildContext context) {
    final items = context.read<TrayCubit>().state;
    // One picked file goes straight to the link page; with none or several,
    // the page lets the user choose.
    context.push('/remote', extra: items.length == 1 ? items.first.path : null);
  }

  Future<void> _copyBrowserLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _browserUrl));
    if (context.mounted) {
      toast(context, 'common.link_copied'.tr(), type: ToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader('home.other_ways'.tr()),
          AppGroup(
            child: Column(
              children: [
                AppListTile(
                  leading: AppSvgIcon(
                    AppIcons.send,
                    size: 20,
                    color: cs.primary,
                  ),
                  title: Text('home.send_link'.tr()),
                  subtitle: Text('home.send_link_sub'.tr()),
                  trailing: AppSvgIcon(
                    AppIcons.chevronRight,
                    size: 16,
                    color: cs.mutedForeground,
                  ),
                  onTap: () => _sendAsLink(context),
                ),
                const AppRowDivider(),
                AppListTile(
                  leading: AppSvgIcon(
                    AppIcons.globePublic,
                    size: 20,
                    color: cs.primary,
                  ),
                  title: Text('home.use_browser'.tr()),
                  subtitle: Text('home.use_browser_sub'.tr()),
                  trailing: AppSvgIcon(
                    AppIcons.copyDuplicate,
                    size: 16,
                    color: cs.mutedForeground,
                  ),
                  onTap: () => _copyBrowserLink(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
