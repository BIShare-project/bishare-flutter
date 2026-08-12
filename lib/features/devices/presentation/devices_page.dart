import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/devices/device_registry.dart';
import '../../../core/ui/app_ui.dart';
import 'devices_cubit.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../web_nearby/data/web_nearby_service.dart';
import '../../web_nearby/presentation/web_nearby_cubit.dart';
import 'widgets/device_sort_bar.dart';
import 'widgets/known_device_row.dart';

/// The Devices dashboard: every peer this device has ever known, in two
/// sections — "Online now" (currently discovered) and "Known devices"
/// (remembered roster + favorites) — with search, sort, and a per-device
/// detail sheet (stats + rename / favorite / auto-accept / forget).
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
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
                  ),
                  DeviceSortBar(value: state.sort, onChanged: cubit.setSort),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: ShadInput(
                      placeholder: Text('devices.search_placeholder'.tr()),
                      leading: const AppSvgIcon(AppIcons.search, size: 16),
                      onChanged: cubit.setQuery,
                    ),
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
                            padding: const EdgeInsets.only(top: 4, bottom: 28),
                            children: [
                              if (online.isNotEmpty) ...[
                                AppSectionHeader(
                                  'devices.online_now'.tr(),
                                  trailing: Text('${online.length}'),
                                ),
                                _group(online),
                              ],
                              if (known.isNotEmpty) ...[
                                AppSectionHeader(
                                  'devices.known'.tr(),
                                  trailing: Text('${known.length}'),
                                ),
                                _group(known),
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

  Widget _group(List<KnownDeviceView> devices) => AppGroup(
    child: Column(
      children: [
        for (var i = 0; i < devices.length; i++) ...[
          if (i > 0) const AppRowDivider(indent: 68),
          KnownDeviceRow(device: devices[i]),
        ],
      ],
    ),
  );
}

/// Browsers on this network (the app↔web Nearby bridge): each row is a live
/// peer from bishare.app/transfer's Nearby tab — tap send, pick files, and
/// they stream browser-ward over WebRTC. Hidden while the bridge is off or
/// no browser is around.
class _BrowsersNearbySection extends StatelessWidget {
  const _BrowsersNearbySection();

  Future<void> _send(BuildContext context, String peerId) async {
    final cubit = context.read<WebNearbyCubit>();
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths =
        res?.files.map((f) => f.path).whereType<String>().toList() ?? const [];
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
            AppGroup(
              child: Column(
                children: [
                  for (var i = 0; i < state.peers.length; i++) ...[
                    if (i > 0) const AppRowDivider(indent: 68),
                    _BrowserRow(
                      peer: state.peers[i],
                      sending: state.sendingTo.contains(state.peers[i].peerId),
                      onSend: () => _send(context, state.peers[i].peerId),
                    ),
                  ],
                ],
              ),
            ),
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
    final cs = ShadTheme.of(context).colorScheme;
    return ListTile(
      onTap: sending ? null : onSend,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(peer.emoji, style: const TextStyle(fontSize: 20)),
      ),
      title: Text(
        peer.alias,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        'devices.browser_subtitle'.tr(),
        style: TextStyle(fontSize: 12, color: cs.mutedForeground),
      ),
      trailing: sending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : AppSvgIcon(AppIcons.send, size: 18, color: cs.primary),
    );
  }
}
