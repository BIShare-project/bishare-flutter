import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/app_ui.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSvgIcon(AppIcons.circleAlert, size: 44, color: t.danger),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: t.text),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'common.try_again'.tr(),
              icon: AppIcons.refreshSync,
              size: AppButtonSize.large,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
