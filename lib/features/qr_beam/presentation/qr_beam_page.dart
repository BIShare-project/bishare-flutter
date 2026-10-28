import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/ui/app_ui.dart';

/// QR Beam entry — pick a direction. QR Beam transfers a small file over an
/// animated stream of QR codes when there's no Wi-Fi, hotspot, or Bluetooth at
/// all (purely screen → camera). One device shows the codes, the other scans.
class QrBeamPage extends StatelessWidget {
  const QrBeamPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Column(
          children: [
            AppScreenHeader(
              title: 'qr_beam.title'.tr(),
              subtitle: 'qr_beam.subtitle'.tr(),
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: AppResponsivePane(
                maxWidth: 560,
                child: ListView(
                  children: [
                    _Choice(
                      icon: AppIcons.qrShare,
                      title: 'qr_beam.send_title'.tr(),
                      subtitle: 'qr_beam.send_desc'.tr(),
                      onTap: () => context.push('/qr-beam/send'),
                    ),
                    // Receiving needs a camera to scan the QR stream:
                    // mobile-only (supportsCameraScan), send-only on desktop.
                    if (supportsCameraScan) ...[
                      const AppRowDivider(indent: 70),
                      _Choice(
                        icon: AppIcons.scanDocument,
                        title: 'qr_beam.receive_title'.tr(),
                        subtitle: 'qr_beam.receive_desc'.tr(),
                        onTap: () => context.push('/qr-beam/receive'),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                      child: Text(
                        'qr_beam.hint'.tr(),
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A direction: a round icon, what it does, a chevron.
class _Choice extends StatelessWidget {
  const _Choice({
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
    final t = context.tokens;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          tapHaptic();
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: AppSvgIcon(icon, size: 21, color: t.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppType.rowStrong.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
                AppSvgIcon(AppIcons.chevronRight, size: 18, color: t.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
