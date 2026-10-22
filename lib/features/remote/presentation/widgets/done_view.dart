import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/config/feature_flags.dart';
import '../../../../core/di/locator.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../vault/presentation/drive/drive_actions.dart';
import '../../data/cloud_transfer_service.dart';

/// What the Share button sends: the file's name and size, how long the link
/// lasts, a line saying what BIShare is, then the link. Most people who get a
/// BIShare link have never heard of it, and a bare URL told them nothing.
/// Copy still copies the bare link, for pasting into a browser.
String _shareMessage(CloudUploadResult result) {
  final name = result.fileName;
  final size = result.fileSize;
  if (name == null || size == null) return result.url;
  return 'remote.share_message'.tr(
    namedArgs: {'name': name, 'size': formatBytes(size), 'url': result.url},
  );
}

class DoneView extends StatelessWidget {
  const DoneView({super.key, required this.result, this.path});

  final CloudUploadResult result;

  /// The file that was sent, for "Save to Drive".
  final String? path;

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
            result.encrypted
                ? 'remote.done_hint_encrypted'.tr()
                : 'remote.done_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (result.encrypted) AppBadge('remote.badge_e2e'.tr()),
              if (result.oneTime) AppBadge('remote.badge_one_time'.tr()),
              AppBadge('remote.badge_expires_24h'.tr()),
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
                      toast(
                        context,
                        'common.link_copied'.tr(),
                        type: ToastType.success,
                      );
                    }
                  },
                  // Long words (Russian) shrink to fit a narrow phone.
                  child: Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('common.copy'.tr()),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  leading: const AppSvgIcon(AppIcons.shareLink, size: 18),
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text: _shareMessage(result),
                      subject: result.fileName,
                    ),
                  ),
                  child: Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('common.share'.tr()),
                    ),
                  ),
                ),
              ),
            ],
          ),
          _KeepLonger(path: path),
        ],
      ),
    );
  }
}

/// Under a link that ends in 24 hours: where the file can stay longer. Drive
/// keeps it, and a link from Drive lasts up to 30 days or until it is turned
/// off. Nothing unless Drive is on for this device (the vault_enabled flag).
class _KeepLonger extends StatefulWidget {
  const _KeepLonger({required this.path});

  final String? path;

  @override
  State<_KeepLonger> createState() => _KeepLongerState();
}

class _KeepLongerState extends State<_KeepLonger> {
  bool _saved = false;

  Future<void> _save(String path) async {
    final ok = await saveToDrive(context, [path]);
    if (ok && mounted) setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final flags = getIt<FeatureFlags>();
    return ListenableBuilder(
      listenable: flags,
      builder: (context, _) {
        if (!flags.vaultVisible) return const SizedBox.shrink();
        final cs = ShadTheme.of(context).colorScheme;
        final path = widget.path;
        final ready = driveReady;
        final canSave = ready && path != null && File(path).existsSync();
        return AppCard(
          margin: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'remote.keep_longer_title'.tr(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (_saved
                        ? 'remote.keep_longer_saved'
                        : 'remote.keep_longer_body')
                    .tr(),
                style: TextStyle(fontSize: 13, color: cs.mutedForeground),
              ),
              if (!_saved && (canSave || !ready)) ...[
                const SizedBox(height: 12),
                ShadButton.outline(
                  leading: const AppSvgIcon(AppIcons.cloudDone, size: 18),
                  onPressed: canSave
                      ? () => _save(path)
                      : () => context.push('/drive-account'),
                  child: Text(
                    (canSave
                            ? 'vault.save_to_drive'
                            : 'remote.keep_longer_setup')
                        .tr(),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
