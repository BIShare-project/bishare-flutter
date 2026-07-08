import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';

class MyDeviceCard extends StatelessWidget {
  const MyDeviceCard({super.key, 
    required this.alias,
    required this.deviceType,
    this.hidden = false,
  });
  final String alias;
  final String deviceType;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppCard(
      gradient: true,
      accent: hidden ? cs.mutedForeground : null,
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          AppAvatar(icon: iconForDevice(deviceType), size: 50, online: !hidden),
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
                Row(
                  children: [
                    AppSvgIcon(
                      hidden ? AppIcons.eyeOff : AppIcons.wifi,
                      size: 13,
                      color: cs.mutedForeground,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hidden
                          ? 'home.hidden_not_discoverable'.tr()
                          : 'home.visible_ready'.tr(),
                      style: TextStyle(fontSize: 13, color: cs.mutedForeground),
                    ),
                  ],
                ),
              ],
            ),
          ),
          hidden
              ? AppStatusPill('home.hidden'.tr(), color: cs.mutedForeground)
              : AppStatusPill('home.online'.tr()),
        ],
      ),
    );
  }
}
