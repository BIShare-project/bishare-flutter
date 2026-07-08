import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_svg_icon.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSvgIcon(AppIcons.circleAlert, size: 44, color: cs.destructive),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.foreground),
            ),
            const SizedBox(height: 20),
            ShadButton(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.refreshSync, size: 18),
              onPressed: onRetry,
              child: Text('common.try_again'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
