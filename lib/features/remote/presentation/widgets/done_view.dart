import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/ui/app_ui.dart';
import '../../data/cloud_transfer_service.dart';

class DoneView extends StatelessWidget {
  const DoneView({super.key, required this.result});

  final CloudUploadResult result;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          BiShareQr(data: result.url),
          const SizedBox(height: 18),
          Text(
            result.code,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan the code or open the link on any device.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (result.oneTime) const AppBadge('One-time'),
              const AppBadge('Expires in 24h'),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  size: ShadButtonSize.lg,
                  leading: const AppSvgIcon(AppIcons.copyDuplicate, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: result.url));
                    if (context.mounted) {
                      toast(context, 'common.link_copied'.tr(), type: ToastType.success);
                    }
                  },
                  child: Text('common.copy'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  leading: const AppSvgIcon(AppIcons.shareLink, size: 18),
                  onPressed: () =>
                      SharePlus.instance.share(ShareParams(text: result.url)),
                  child: Text('common.share'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
