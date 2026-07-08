import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_svg_icon.dart';

/// A centered empty/placeholder state: a rounded icon tile, a title, and a
/// supporting message.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final String icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: cs.muted,
              borderRadius: BorderRadius.circular(26),
            ),
            child: AppSvgIcon(icon, size: 38, color: cs.mutedForeground),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: cs.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
