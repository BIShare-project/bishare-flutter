import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/constants/protocol.dart';

class VersionFooter extends StatelessWidget {
  const VersionFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
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
    );
  }
}
