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
                    AppChoiceRow(
                      icon: AppIcons.qrShare,
                      title: 'qr_beam.send_title'.tr(),
                      subtitle: 'qr_beam.send_desc'.tr(),
                      onTap: () => context.push('/qr-beam/send'),
                    ),
                    // Receiving needs a camera to scan the QR stream:
                    // mobile-only (supportsCameraScan), send-only on desktop.
                    if (supportsCameraScan) ...[
                      const AppRowDivider(indent: 70),
                      AppChoiceRow(
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
