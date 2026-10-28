import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/cloud.dart';
import '../../../../core/ui/app_ui.dart';

/// Sender is waiting for a receiver to scan the live-stream code. Shows the
/// `bishare-stream://<code>` QR + code, ephemeral (nothing is stored server-side).
class StreamWaitingView extends StatelessWidget {
  const StreamWaitingView({super.key, required this.code, this.keyFragment});

  final String code;

  /// The end-to-end key when the sender sealed the file. It rides ONLY in the
  /// QR (after `#`), never in the displayed code and never through the relay.
  final String? keyFragment;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          BiShareQr(
            data:
                '${CloudConfig.schemeStream}://$code'
                '${keyFragment == null ? '' : '#k=$keyFragment'}',
          ),
          const SizedBox(height: 18),
          Text(
            code,
            style: AppType.title.copyWith(
              color: t.text,
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (keyFragment != null) ...[
            const SizedBox(height: 10),
            AppBadge('remote.badge_e2e'.tr()),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'remote.waiting_scan'.tr(),
                style: AppType.secondary.copyWith(color: t.text2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'remote.keep_open'.tr(),
            textAlign: TextAlign.center,
            style: AppType.secondary.copyWith(color: t.text2),
          ),
        ],
      ),
    );
  }
}
