import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/ui/app_ui.dart';
import 'widgets/web_access_body.dart';

/// Shows the "Browser access" prompt with two tabs (feature #11):
///
/// * **LAN** — a QR code + the `http://<ip>:port` URL any device on the same
///   network can open to send/download files without the app.
/// * **Cloud link** — pick a file and upload it as a 24h one-time cloud
///   transfer (the Remote-Share flow, reused) for devices NOT on this network.
Future<void> showWebAccess(BuildContext context) async {
  final ip = await LocalIp.resolve();
  final url = 'http://$ip:${BISharePort.main}';
  if (!context.mounted) return;
  await showAppSheet<void>(
    context,
    icon: AppIcons.globePublic,
    title: 'inbox.browser_access'.tr(),
    subtitle: 'inbox.browser_access_subtitle'.tr(),
    builder: (ctx) => WebAccessBody(url: url),
  );
}
