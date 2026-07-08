import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

class PickView extends StatelessWidget {
  const PickView({
    super.key,
    required this.oneTime,
    required this.onOneTime,
    required this.shareViaWeb,
    required this.onShareViaWeb,
    required this.onMedia,
    required this.onFile,
  });

  final bool oneTime;
  final ValueChanged<bool> onOneTime;
  final bool shareViaWeb;
  final ValueChanged<bool> onShareViaWeb;
  final VoidCallback onMedia;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.primary,
                  Color.lerp(cs.primary, Colors.black, 0.22)!,
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: AppSvgIcon(
              AppIcons.send,
              size: 38,
              color: cs.primaryForeground,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'remote.send_to_anyone'.tr(),
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'remote.send_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              color: cs.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.border.withValues(alpha: 0.8)),
            ),
            child: Column(
              children: [
                _OptionRow(
                  icon: AppIcons.globePublic,
                  iconColor: const Color(0xFF2563EB),
                  title: 'remote.share_via_web'.tr(),
                  subtitle: shareViaWeb
                      ? 'remote.share_via_web_on_subtitle'.tr()
                      : 'remote.share_via_web_off_subtitle'.tr(),
                  trailing: ShadSwitch(
                    value: shareViaWeb,
                    onChanged: onShareViaWeb,
                  ),
                ),
                if (shareViaWeb) ...[
                  Divider(height: 1, indent: 56, color: cs.border),
                  _OptionRow(
                    icon: AppIcons.flame,
                    iconColor: const Color(0xFFEA580C),
                    title: 'remote.one_time_download'.tr(),
                    subtitle: 'remote.one_time_download_subtitle'.tr(),
                    trailing: ShadSwitch(value: oneTime, onChanged: onOneTime),
                  ),
                  Divider(height: 1, indent: 56, color: cs.border),
                  _OptionRow(
                    icon: AppIcons.clock,
                    iconColor: cs.primary,
                    title: 'remote.expires_24h'.tr(),
                    subtitle: 'remote.expires_24h_subtitle'.tr(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.image, size: 18),
              onPressed: onMedia,
              child: Text('remote.choose_photo_video'.tr()),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ShadButton.outline(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.fileDocument, size: 18),
              onPressed: onFile,
              child: Text('remote.choose_file'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AppSvgIcon(icon, size: 20, color: iconColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12.5, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
