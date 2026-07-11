import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_links.dart';
import '../../../core/ui/app_ui.dart';

/// Shown from the empty nearby state: help a peer who doesn't have BIShare yet
/// install it — a QR to the download page (scan with any camera → the site
/// forwards to the right store), explicit store buttons, and a share link.
Future<void> showInviteDeviceSheet(BuildContext context) => showAppSheet<void>(
  context,
  title: 'invite.title'.tr(),
  subtitle: 'invite.subtitle'.tr(),
  icon: AppIcons.qrShare,
  builder: (ctx) => const _InviteBody(),
);

class _InviteBody extends StatelessWidget {
  const _InviteBody();

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: BiShareQr(data: AppLinks.download, size: 200)),
        const SizedBox(height: 14),
        Text(
          'invite.scan_hint'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cs.mutedForeground),
        ),
        const SizedBox(height: 18),
        AppGroup(
          child: Column(
            children: [
              AppSheetAction(
                icon: AppIcons.externalLink,
                label: 'invite.app_store'.tr(),
                onTap: () => _open(AppLinks.appStore),
              ),
              const AppRowDivider(),
              AppSheetAction(
                icon: AppIcons.externalLink,
                label: 'invite.google_play'.tr(),
                onTap: () => _open(AppLinks.playStore),
              ),
              const AppRowDivider(),
              AppSheetAction(
                icon: AppIcons.shareLink,
                label: 'invite.share'.tr(),
                onTap: () =>
                    SharePlus.instance.share(ShareParams(text: AppLinks.shareMessage)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
