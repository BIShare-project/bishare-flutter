import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/ui/app_ui.dart';

/// QR Beam entry — pick a direction. QR Beam transfers a small file over an
/// animated stream of QR codes when there's no Wi-Fi, hotspot, or Bluetooth at
/// all (purely screen → camera). One device shows the codes, the other scans.
class QrBeamPage extends StatelessWidget {
  const QrBeamPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
                    cs.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: AppResponsivePane(
              maxWidth: 640,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppScreenHeader(
                    title: 'qr_beam.title'.tr(),
                    subtitle: 'qr_beam.subtitle'.tr(),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 8),
                  _OptionCard(
                    icon: AppIcons.qrShare,
                    title: 'qr_beam.send_title'.tr(),
                    subtitle: 'qr_beam.send_desc'.tr(),
                    onTap: () {
                      tapHaptic();
                      context.push('/qr-beam/send');
                    },
                  ),
                  // Receiving needs a camera to scan the QR stream — unavailable
                  // on Windows/Linux (no mobile_scanner). QR Beam is send-only there.
                  if (supportsCameraScan)
                    _OptionCard(
                      icon: AppIcons.scanDocument,
                      title: 'qr_beam.receive_title'.tr(),
                      subtitle: 'qr_beam.receive_desc'.tr(),
                      onTap: () {
                        tapHaptic();
                        context.push('/qr-beam/receive');
                      },
                    ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: Text(
                      'qr_beam.hint'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: cs.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: AppSvgIcon(icon, size: 22, color: cs.primary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, height: 1.35, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          AppSvgIcon(AppIcons.chevronRight, size: 18, color: cs.mutedForeground),
        ],
      ),
    );
  }
}
