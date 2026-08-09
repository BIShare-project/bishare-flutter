import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../discovery/presentation/discovery_cubit.dart';

class Header extends StatelessWidget {
  const Header({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BIShare',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: cs.foreground,
                  ),
                ),
                BlocBuilder<DiscoveryCubit, List<DiscoveredDevice>>(
                  builder: (context, devices) => Text(
                    devices.isEmpty
                        ? 'home.searching_devices'.tr()
                        : 'home.devices_nearby'.plural(devices.length),
                    style: TextStyle(fontSize: 13, color: cs.mutedForeground),
                  ),
                ),
              ],
            ),
          ),
          // Offline Nearby (MultipeerConnectivity radar) — Apple only for now.
          if (Platform.isIOS || Platform.isMacOS)
            AppIconButton(
              icon: AppIcons.wifi,
              onPressed: () => context.push('/nearby'),
            ),
          // Scan a QR to receive a remote transfer / share / room.
          // Camera scanning is unavailable on Windows/Linux (no mobile_scanner).
          if (supportsCameraScan)
            AppIconButton(
              icon: AppIcons.scanDocument,
              onPressed: () => context.push('/scan'),
            ),
          // QR Beam: offline file transfer over a stream of QR codes (no network).
          AppIconButton(
            icon: AppIcons.qrShare,
            onPressed: () => context.push('/qr-beam'),
          ),
          // Remote share: send a file as a link + QR that works anywhere.
          AppIconButton(
            icon: AppIcons.send,
            onPressed: () => context.push('/remote'),
          ),
          AppIconButton(
            icon: AppIcons.refreshSync,
            onPressed: () => context.read<DiscoveryCubit>().restart(),
          ),
        ],
      ),
    );
  }
}
