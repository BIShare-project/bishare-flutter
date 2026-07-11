import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/devices/device_registry.dart';
import '../../../core/ui/app_ui.dart';
import 'devices_cubit.dart';
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
