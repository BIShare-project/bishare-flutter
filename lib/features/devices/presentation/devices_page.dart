import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/devices/device_registry.dart';
import '../../../core/io/picked_mtime.dart';
import '../../../core/ui/app_ui.dart';
import '../../web_nearby/data/web_nearby_service.dart';
import '../../web_nearby/presentation/web_nearby_cubit.dart';
import 'device_detail_sheet.dart';
import 'devices_cubit.dart';

/// The Devices dashboard: every peer this device has ever known, in two
/// sections, "Online now" (currently discovered) and "Known devices"
/// (remembered roster + favorites), then browsers nearby. Search hides
/// behind the header's magnifier and the order is a sheet, as in History
/// and Drive; a row opens the device's sheet (stats + rename / favorite /
/// auto-accept / forget).
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _searchOpen = false;

  void _closeSearch(DevicesCubit cubit) {
    cubit.setQuery('');
    setState(() => _searchOpen = false);
  }

  Future<void> _sortSheet(BuildContext context, DevicesCubit cubit) async {
    final picked = await showAppSheet<DeviceSort>(
      context,
      icon: AppIcons.sort,
      title: 'devices.sort_title'.tr(),
      builder: (ctx) => AppSheetGroup(
        first: true,
        indent: 4,
        children: [
          for (final s in DeviceSort.values)
            AppSheetAction(
              label: s.label,
              selected: s == cubit.state.sort,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ],
      ),
    );
    if (picked != null) cubit.setSort(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: BlocBuilder<DevicesCubit, DevicesState>(
          builder: (context, state) {
            final cubit = context.read<DevicesCubit>();
            final online = state.onlineNow;
            final known = state.knownOffline;
            return AppResponsivePane(
              maxWidth: 760,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: 'devices.title'.tr(),
                    subtitle: 'devices.devices_count'.plural(state.all.length),
                    onBack: () => Navigator.of(context).maybePop(),
                    actions: [
                      AppIconButton(
                        icon: AppIcons.search,
                        tooltip: 'devices.search_placeholder'.tr(),
                        onPressed: () => _searchOpen
                            ? _closeSearch(cubit)
                            : setState(() => _searchOpen = true),
                      ),
                      AppIconButton(
                        icon: AppIcons.sort,
                        tooltip: 'devices.sort_title'.tr(),
                        onPressed: () => _sortSheet(context, cubit),
                      ),
                    ],
                  ),
                  if (_searchOpen)
                    AppSearchRow(
                      hint: 'devices.search_placeholder'.tr(),
                      initial: state.query,
                      onChanged: cubit.setQuery,
                      onCancel: () => _closeSearch(cubit),
                    ),
                  Expanded(
                    child: (online.isEmpty && known.isEmpty)
                        ? AppEmptyState(
                            icon: AppIcons.smartphone,
                            title: state.all.isEmpty
                                ? 'devices.empty_none_title'.tr()
                                : 'devices.empty_no_matches_title'.tr(),
                            message: state.all.isEmpty
                                ? 'devices.empty_none_message'.tr()
                                : 'devices.empty_no_matches_message'.tr(),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 28),
                            children: [
                              if (online.isNotEmpty) ...[
                                AppSectionHeader(
                                  'devices.online_now'.tr(),
                                  trailing: Text('${online.length}'),
                                ),
                                ..._rows(online),
                              ],
                              if (known.isNotEmpty) ...[
                                AppSectionHeader(
                                  'devices.known'.tr(),
                                  trailing: Text('${known.length}'),
                                ),
                                ..._rows(known),
                              ],
                              const _BrowsersNearbySection(),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static List<Widget> _rows(List<KnownDeviceView> devices) => [
    for (var i = 0; i < devices.length; i++) ...[
      if (i > 0) const AppRowDivider(indent: 70),
      KnownDeviceRow(device: devices[i]),
    ],
  ];
}

/// One roster row: avatar with a live presence dot, display name (+
/// favorite star), model + presence. Tap opens the device sheet.
class KnownDeviceRow extends StatelessWidget {
  const KnownDeviceRow({super.key, required this.device});
  final KnownDeviceView device;

  @override
  Widget build(BuildContext context) {
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
        deviceSubtitle(device),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AppIconButton(
        icon: AppIcons.moreMenu,
        tooltip: 'inbox.more'.tr(),
        onPressed: () => showDeviceDetailSheet(context, device),
      ),
    );
  }
}

/// Browsers on this network (the app↔web Nearby bridge): each row is a live
/// peer from bishare.app/transfer's Nearby tab; tap, pick files, and they
/// stream browser-ward over WebRTC. Hidden while the bridge is off or no
/// browser is around.
class _BrowsersNearbySection extends StatelessWidget {
  const _BrowsersNearbySection();

  Future<void> _send(BuildContext context, String peerId) async {
    final cubit = context.read<WebNearbyCubit>();
    final paths = await pickFilePaths();
    if (paths.isEmpty) return;
    await cubit.sendFiles(peerId, [for (final p in paths) File(p)]);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WebNearbyCubit, WebNearbyState>(
      builder: (context, state) {
        if (state.peers.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              'devices.browsers_nearby'.tr(),
              trailing: Text('${state.peers.length}'),
            ),
            for (var i = 0; i < state.peers.length; i++) ...[
              if (i > 0) const AppRowDivider(indent: 70),
              _BrowserRow(
                peer: state.peers[i],
                sending: state.sendingTo.contains(state.peers[i].peerId),
                onSend: () => _send(context, state.peers[i].peerId),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _BrowserRow extends StatelessWidget {
  const _BrowserRow({
    required this.peer,
    required this.sending,
    required this.onSend,
  });

  final WebNearbyPeer peer;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AppListTile(
      onTap: sending ? null : onSend,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.sunken, shape: BoxShape.circle),
        child: Text(peer.emoji, style: const TextStyle(fontSize: 19)),
      ),
      title: Text(peer.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('devices.browser_subtitle'.tr()),
      trailing: sending
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            )
          : AppSvgIcon(AppIcons.send, size: 20, color: t.accent),
    );
  }
}
