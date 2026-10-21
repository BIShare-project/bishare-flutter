import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/config/feature_flags.dart';
import '../../../../core/constants/protocol.dart';
import '../../../../core/di/locator.dart';

/// App name and version. Seven taps switch BIShare Drive testing on or off for
/// this device, and only while the server flag is "internal" (drive-plan.md
/// task 3.1); otherwise the taps do nothing.
class VersionFooter extends StatefulWidget {
  const VersionFooter({super.key});

  @override
  State<VersionFooter> createState() => _VersionFooterState();
}

class _VersionFooterState extends State<VersionFooter> {
  int _taps = 0;
  DateTime _first = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _tap() async {
    final now = DateTime.now();
    if (now.difference(_first) > const Duration(seconds: 3)) {
      _first = now;
      _taps = 0;
    }
    if (++_taps < 7) return;
    _taps = 0;
    final flags = getIt<FeatureFlags>();
    if (!flags.vaultInternal) return;
    final on = !flags.vaultTester;
    await flags.setVaultTester(on);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text((on ? 'vault.tester_on' : 'vault.tester_off').tr()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Center(
          child: Column(
            children: [
              Text(
                'BIShare',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.mutedForeground,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Version ${BIShareConfig.version}',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.mutedForeground.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
