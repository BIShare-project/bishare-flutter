import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import 'web_access_cloud_tab.dart';

/// The Browser-access sheet body: a segmented two-tab switcher between the
/// LAN QR/URL and the "Cloud link" flow (feature #11).
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
        _WebAccessTabBar(
          index: _tab,
          labels: ['inbox.web_tab_lan'.tr(), 'inbox.web_tab_cloud'.tr()],
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 18),
        if (_tab == 0)
          _LanTab(url: widget.url)
        else
          const WebAccessCloudTab(),
      ],
    );
  }
}

/// Segmented pill tab bar — the same style as the History filter / Devices
/// sort bars.
class _WebAccessTabBar extends StatelessWidget {
  const _WebAccessTabBar({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index == i ? cs.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: index == i
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: index == i ? FontWeight.w700 : FontWeight.w500,
                      color: index == i ? cs.foreground : cs.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The LAN tab: QR + copyable URL (the pre-#11 sheet content), plus the iOS
/// foreground caveat — the local server stops when the app is backgrounded.
class _LanTab extends StatelessWidget {
  const _LanTab({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BiShareQr(data: url),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: cs.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: cs.foreground,
                  ),
                ),
              ),
              ShadIconButton.ghost(
                icon: const AppSvgIcon(AppIcons.copyDuplicate, size: 18),
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
        if (Platform.isIOS) ...[
          const SizedBox(height: 12),
          Text(
            'inbox.web_ios_note'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.mutedForeground),
          ),
        ],
      ],
    );
  }
}
