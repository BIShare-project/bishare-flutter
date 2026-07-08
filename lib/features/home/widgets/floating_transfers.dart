import 'package:flutter/material.dart';

import '../../../core/ui/app_ui.dart';
import 'receive_banner.dart';
import 'send_banner.dart';

/// The bottom-pinned stack of live transfer cards (receive above send). Renders
/// nothing when idle, so it doesn't block taps on the content underneath.
class FloatingTransfers extends StatelessWidget {
  const FloatingTransfers({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: AppResponsivePane(
        maxWidth: 960,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [ReceiveBanner(), SendBanner()],
          ),
        ),
      ),
    );
  }
}
