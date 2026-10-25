import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/ui/app_showcase.dart';
import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../discovery/presentation/discovery_cubit.dart';
import '../../settings/domain/settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import 'device_section.dart';

/// The Send tab's header: this device's name, a line saying whether it is
/// visible and how many devices are near (it opens the device list), and the
/// scan button for receiving by QR. The other old header buttons (QR Beam,
/// Secure Link, Nearby, refresh) moved into the send sheet and the device
/// list.
class SendHeader extends StatelessWidget {
  const SendHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final settings = context.select<SettingsCubit, Settings>((c) => c.state);
    final hidden = settings.visibility.name == 'hidden';
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShowcase(
                  showcaseKey: ShowcaseKeys.homeDevice,
                  title: 'showcase.home_device_title'.tr(),
                  description: 'showcase.home_device_body'.tr(),
                  targetRadius: 8,
                  child: Semantics(
                    header: true,
                    child: Text(
                      settings.alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.deviceName.copyWith(color: t.text),
                    ),
                  ),
                ),
                AppShowcase(
                  showcaseKey: ShowcaseKeys.homeNearby,
                  title: 'showcase.home_nearby_title'.tr(),
                  description: 'showcase.home_nearby_body'.tr(),
                  targetRadius: 8,
                  child:
                      BlocSelector<DiscoveryCubit, List<DiscoveredDevice>, int>(
                        selector: (d) => d.length,
                        builder: (context, n) => Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => showDeviceList(context),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 32),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hidden ? t.text3 : t.ok,
                                    ),
                                  ),
                                  const SizedBox(width: 7),
                                  Flexible(
                                    child: Text(
                                      [
                                        hidden
                                            ? 'home.hidden'.tr()
                                            : 'compose.visible'.tr(),
                                        n == 0
                                            ? 'home.searching_devices'.tr()
                                            : 'home.devices_nearby'.plural(n),
                                      ].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.secondary.copyWith(
                                        color: t.text2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  AppSvgIcon(
                                    AppIcons.chevronRight,
                                    size: 14,
                                    color: t.text3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                ),
              ],
            ),
          ),
          if (supportsCameraScan)
            AppShowcase(
              showcaseKey: ShowcaseKeys.homeActions,
              title: 'showcase.home_actions_title'.tr(),
              description: 'showcase.home_actions_body'.tr(),
              targetRadius: 22,
              child: AppIconButton(
                icon: AppIcons.scanDocument,
                tooltip: 'scanner.title'.tr(),
                onPressed: () => context.push('/scan'),
              ),
            ),
        ],
      ),
    );
  }
}

/// The nearby devices as a list (the old home list, kept whole): send,
/// request files, favourite, details, browsers on this network, and the ways
/// that work with nobody near.
Future<void> showDeviceList(BuildContext context) => showGlassModal<void>(
  context,
  builder: (_) => const Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: DeviceSection(list: true),
  ),
);
