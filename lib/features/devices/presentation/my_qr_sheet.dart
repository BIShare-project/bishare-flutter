import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/deeplink/deep_link.dart';
import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/ui/app_ui.dart';

/// "Show my QR": a code with this device's addresses, name and fingerprint.
/// Scanned with BIShare on another device on the same network, it reaches
/// this one directly, without waiting for discovery (which some office,
/// hotel and router networks block).
Future<void> showMyQrSheet(BuildContext context) async {
  final identity = getIt<DeviceIdentity>();
  final hosts = await LocalIp.all();
  if (!context.mounted) return;
  await showAppSheet<void>(
    context,
    icon: AppIcons.qrShare,
    title: 'connect.my_qr_title'.tr(),
    subtitle: hosts.isEmpty
        ? 'connect.no_network'.tr()
        : 'connect.my_qr_subtitle'.tr(),
    builder: (ctx) => hosts.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BiShareQr(
                  data: ConnectLink.uriFor(
                    hosts: hosts,
                    fingerprint: identity.fingerprint,
                    name: identity.alias,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  identity.alias,
                  style: Theme.of(ctx).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  hosts.join(' · '),
                  style: Theme.of(ctx).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
  );
}
