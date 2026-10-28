import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/app_ui.dart';
import 'web_access_cloud_tab.dart';

/// The Browser-access sheet body: LAN (QR and address) or Cloud link
/// (feature #11), switched by a segmented control.
class WebAccessBody extends StatefulWidget {
  const WebAccessBody({super.key, required this.url});

  final String url;

  @override
  State<WebAccessBody> createState() => _WebAccessBodyState();
}

class _WebAccessBodyState extends State<WebAccessBody> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSegmented<int>(
          value: _tab,
          options: [
            (0, 'inbox.web_tab_lan'.tr()),
            (1, 'inbox.web_tab_cloud'.tr()),
          ],
          onChanged: (i) => setState(() => _tab = i),
          margin: EdgeInsets.zero,
        ),
        const SizedBox(height: 18),
        if (_tab == 0) _LanTab(url: widget.url) else const WebAccessCloudTab(),
      ],
    );
  }
}

/// The LAN tab: QR and the copyable address, and what to do with it. On iOS
/// the local server stops when the app goes to the background, so the hint
/// says to keep it open.
class _LanTab extends StatelessWidget {
  const _LanTab({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BiShareQr(data: url),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.row.copyWith(
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              AppIconButton(
                icon: AppIcons.copyDuplicate,
                tooltip: 'common.copy'.tr(),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    toast(
                      context,
                      'inbox.address_copied'.tr(),
                      type: ToastType.success,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          (Platform.isIOS ? 'inbox.web_ios_note' : 'inbox.web_lan_hint').tr(),
          textAlign: TextAlign.center,
          style: AppType.secondary.copyWith(color: t.text2),
        ),
      ],
    );
  }
}
