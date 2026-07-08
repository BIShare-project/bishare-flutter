import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/constants/cloud.dart';
import '../../../../core/ui/app_ui.dart';

/// Sender is waiting for a receiver to scan the live-stream code. Shows the
/// `bishare-stream://<code>` QR + code, ephemeral (nothing is stored server-side).
class StreamWaitingView extends StatelessWidget {
  const StreamWaitingView({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          BiShareQr(data: '${CloudConfig.schemeStream}://$code'),
          const SizedBox(height: 18),
          Text(
            code,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Waiting for the receiver to scan…',
                style: TextStyle(fontSize: 13.5, color: cs.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Keep this screen open. The file streams directly — nothing is '
            'stored online.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.3, color: cs.mutedForeground),
          ),
        ],
      ),
    );
  }
}
