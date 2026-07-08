import 'package:flutter/material.dart';

import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import 'device_row.dart';

/// Wide-layout device grid (2–3 columns) — uses the desktop's landscape width
/// instead of a single stretched column.
class DeviceGrid extends StatelessWidget {
  const DeviceGrid({super.key, required this.devices});
  final List<DiscoveredDevice> devices;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LayoutBuilder(
        builder: (context, c) {
          const spacing = 12.0;
          final cols = c.maxWidth >= 720 ? 3 : 2;
          final w = (c.maxWidth - spacing * (cols - 1)) / cols;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final d in devices)
                SizedBox(
                  width: w,
                  child: AppCard(
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.zero,
                    child: DeviceRow(device: d),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
