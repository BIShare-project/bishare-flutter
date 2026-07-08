import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_links.dart';
import '../../../../core/ui/app_ui.dart';
import 'glyph.dart';

/// Settings → About: legal, help, and community links (privacy policy, terms of
/// service, support, rating, sharing). Mirrors the native iOS "About" menu so
/// the Flutter client keeps parity — every row opens the OS browser, mail app,
/// or share sheet.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader('settings.about'.tr()),
        AppGroup(
          child: Column(
            children: [
              _row(
                cs,
                icon: AppIcons.permissionShield,
                label: 'settings.privacy_policy'.tr(),
                onTap: () => _open(AppLinks.privacy),
              ),
              const AppRowDivider(indent: 58),
              _row(
                cs,
                icon: AppIcons.fileDocument,
                label: 'settings.terms_of_service'.tr(),
                onTap: () => _open(AppLinks.terms),
              ),
              const AppRowDivider(indent: 58),
              _row(
                cs,
                icon: AppIcons.comment,
                label: 'settings.help_support'.tr(),
                onTap: () => _open(AppLinks.help),
              ),
              const AppRowDivider(indent: 58),
              _row(
                cs,
                icon: AppIcons.mailSend,
                label: 'settings.contact_support'.tr(),
                onTap: () => launchUrl(AppLinks.supportMailto),
              ),
              const AppRowDivider(indent: 58),
              _row(
                cs,
                icon: AppIcons.starFavorite,
                label: 'settings.rate_app'.tr(),
                onTap: () => _open(AppLinks.rateUrl),
              ),
              const AppRowDivider(indent: 58),
              _row(
                cs,
                icon: AppIcons.shareLink,
                label: 'settings.share_app'.tr(),
                external: false,
                onTap: () => SharePlus.instance.share(
                  ShareParams(text: AppLinks.shareMessage),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(
    ShadColorScheme cs, {
    required String icon,
    required String label,
    required VoidCallback onTap,
    bool external = true,
  }) {
    return AppListTile(
      leading: Glyph(icon),
      title: Text(label),
      trailing: AppSvgIcon(
        external ? AppIcons.externalLink : AppIcons.chevronRight,
        size: 18,
        color: cs.mutedForeground.withValues(alpha: 0.6),
      ),
      onTap: onTap,
    );
  }

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
