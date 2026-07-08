import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../discovery/presentation/discovery_cubit.dart';
import 'device_grid.dart';
import 'device_row.dart';

class DeviceSection extends StatelessWidget {
  const DeviceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DiscoveryCubit, List<DiscoveredDevice>>(
      builder: (context, devices) {
        if (devices.isEmpty) {
          return AppEmptyState(
            icon: AppIcons.wifi,
            title: 'home.looking_for_devices'.tr(),
            message: 'home.no_devices_message'.tr(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader(
              'home.nearby_devices'.tr(),
              trailing: Text('${devices.length}'),
            ),
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
          ],
        );
      },
    );
  }
}
