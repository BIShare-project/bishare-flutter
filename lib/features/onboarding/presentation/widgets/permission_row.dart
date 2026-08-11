import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

/// A single permission card on the onboarding permission page: an icon, a title +
/// rationale, and a "Continue" button that flips to a green check once granted.
/// The button deliberately does NOT say "Allow" — App Review (guideline
/// 5.1.1(iv)) rejects pre-permission UI whose button mirrors the system
/// prompt's consent wording; "Continue"/"Next" is the required phrasing.
class PermissionRow extends StatelessWidget {
  const PermissionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onAllow,
    this.accent,
  });

  final String icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onAllow;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    const green = Color(0xFF16A34A);
    final tint = accent ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (granted ? green : tint).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: AppSvgIcon(icon, size: 20, color: granted ? green : tint),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (granted)
            const AppSvgIcon(AppIcons.verifiedCheck, size: 24, color: green)
          else
            ShadButton.raw(
              variant: ShadButtonVariant.primary,
              size: ShadButtonSize.sm,
              onPressed: onAllow,
              child: Text('onboarding.perm_continue'.tr()),
            ),
        ],
      ),
    );
  }
}
