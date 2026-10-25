import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/app_type.dart';
import 'app_svg_icon.dart';

/// A centered empty state: a plain glyph (no tile), a title, a message, and
/// an optional [action] (a button that does the obvious next thing).
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final String icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 52, 32, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSvgIcon(icon, size: 34, color: t.text3),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.sheetTitle.copyWith(fontSize: 17, color: t.text),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(fontSize: 14, color: t.text2),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}
