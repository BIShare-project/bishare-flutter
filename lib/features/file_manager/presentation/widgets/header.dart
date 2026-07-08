import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';

class Header extends StatelessWidget {
  const Header({super.key, required this.onBack, required this.onRefresh});
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 6),
      child: Row(
        children: [
          AppIconButton(icon: AppIcons.chevronLeft, onPressed: onBack),
          const SizedBox(width: 2),
          Text(
            'Files',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: cs.foreground,
            ),
          ),
          const Spacer(),
          AppIconButton(icon: AppIcons.refreshSync, onPressed: onRefresh),
        ],
      ),
    );
  }
}
