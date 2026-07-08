import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/ui/app_ui.dart';

/// Shows the "Browser access" prompt: a QR code + the `http://<ip>:port` URL any
/// device on the same network can open to send/download files without the app.
Future<void> showWebAccess(BuildContext context) async {
  final ip = await LocalIp.resolve();
  final url = 'http://$ip:${BISharePort.main}';
  if (!context.mounted) return;
  await showAppSheet<void>(
    context,
    icon: AppIcons.globePublic,
    title: 'inbox.browser_access'.tr(),
    subtitle: 'inbox.browser_access_subtitle'.tr(),
    builder: (ctx) => _WebAccessBody(url: url),
  );
}

class _WebAccessBody extends StatelessWidget {
  const _WebAccessBody({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BiShareQr(data: url),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: cs.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.foreground,
                  ),
                ),
              ),
              ShadIconButton.ghost(
                icon: const AppSvgIcon(AppIcons.copyDuplicate, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    toast(context, 'inbox.address_copied'.tr(), type: ToastType.success);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
