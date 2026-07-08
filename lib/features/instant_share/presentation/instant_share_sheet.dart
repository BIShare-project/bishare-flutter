import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/constants/protocol.dart';
import '../../../core/di/locator.dart';
import '../../../core/network/local_ip.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/ui/app_ui.dart';

/// Shows a QR that any BIShare device on the same Wi-Fi scans to download this
/// file directly — no accept prompt. One-time links (24h) self-destruct after
/// the first download; timed links (5 min) are reusable. Mirrors native
/// `QRShareView`.
Future<void> showInstantShare(
  BuildContext context, {
  required String path,
  required String fileName,
  required String mimeType,
}) {
  return showGlassModal<void>(
    context,
    builder: (ctx) => _InstantShareSheet(
      path: path,
      fileName: fileName,
      mimeType: mimeType,
    ),
  );
}

class _InstantShareSheet extends StatefulWidget {
  const _InstantShareSheet({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;

  @override
  State<_InstantShareSheet> createState() => _InstantShareSheetState();
}

class _InstantShareSheetState extends State<_InstantShareSheet> {
  bool _oneTime = true;
  String? _ip;
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final ip = await LocalIp.resolve();
    if (!mounted) return;
    setState(() => _ip = ip);
    _regenerate();
  }

  void _regenerate() {
    final ip = _ip;
    if (ip == null) return;
    final token = getIt<TransferServer>().createInstantToken(
      path: widget.path,
      fileName: widget.fileName,
      mimeType: widget.mimeType,
      oneTime: _oneTime,
    );
    setState(() {
      _url =
          'http://$ip:${BISharePort.main}${BIShareApi.instant}?token=$token';
    });
  }

  void _setMode(bool oneTime) {
    if (_oneTime == oneTime) return;
    tapHaptic();
    setState(() => _oneTime = oneTime);
    _regenerate();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final url = _url;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSvgIcon(fileIcon(widget.mimeType), size: 28, color: cs.primary),
          const SizedBox(height: 8),
          Text(
            widget.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan with BIShare on any device on this Wi-Fi to download.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.mutedForeground),
          ),
          const SizedBox(height: 16),
          _ModeToggle(oneTime: _oneTime, onChanged: _setMode),
          const SizedBox(height: 18),
          if (url == null)
            const SizedBox(
              height: 214,
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            BiShareQr(data: url),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
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
                      style: TextStyle(fontSize: 12.5, color: cs.foreground),
                    ),
                  ),
                  ShadIconButton.ghost(
                    icon: const AppSvgIcon(AppIcons.copyDuplicate, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        toast(context, 'common.link_copied'.tr(), type: ToastType.success);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.oneTime, required this.onChanged});

  final bool oneTime;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _seg(cs, 'One-time · 24h', AppIcons.flame, oneTime, () => onChanged(true)),
          _seg(cs, 'Timed · 5 min', AppIcons.clock, !oneTime, () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _seg(
    ShadColorScheme cs,
    String label,
    String icon,
    bool active,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? cs.background : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppSvgIcon(
                icon,
                size: 14,
                color: active ? cs.primary : cs.mutedForeground,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? cs.foreground : cs.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
