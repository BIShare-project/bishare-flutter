import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/app_ui.dart';

class PickView extends StatelessWidget {
  const PickView({
    super.key,
    required this.oneTime,
    required this.onOneTime,
    required this.e2e,
    required this.onE2e,
    required this.shareViaWeb,
    required this.onShareViaWeb,
    required this.onMedia,
    required this.onFile,
    this.presetName,
    this.onPreset,
  });

  final bool oneTime;
  final ValueChanged<bool> onOneTime;
  final bool e2e;
  final ValueChanged<bool> onE2e;
  final bool shareViaWeb;
  final ValueChanged<bool> onShareViaWeb;
  final VoidCallback onMedia;
  final VoidCallback onFile;

  /// A file handed over from the Share screen (e.g. "Send as a link"): shown
  /// with a primary "Create link" button, so the options above still apply.
  final String? presetName;
  final VoidCallback? onPreset;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final preset = presetName != null && onPreset != null;
    final options = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
        child: Text(
          'remote.send_subtitle'.tr(),
          style: AppType.body.copyWith(color: t.text2),
        ),
      ),
      AppSwitchRow(
        icon: AppIcons.globePublic,
        title: 'remote.share_via_web'.tr(),
        subtitle: shareViaWeb
            ? 'remote.share_via_web_on_subtitle'.tr()
            : 'remote.share_via_web_off_subtitle'.tr(),
        value: shareViaWeb,
        onChanged: onShareViaWeb,
      ),
      AppSwitchRow(
        icon: AppIcons.passwordLock,
        title: 'remote.e2e_encrypt'.tr(),
        subtitle: e2e
            ? 'remote.e2e_encrypt_on_subtitle'.tr()
            : 'remote.e2e_encrypt_off_subtitle'.tr(),
        value: e2e,
        onChanged: onE2e,
      ),
      if (shareViaWeb) ...[
        AppSwitchRow(
          icon: AppIcons.flame,
          title: 'remote.one_time_download'.tr(),
          subtitle: 'remote.one_time_download_subtitle'.tr(),
          value: oneTime,
          onChanged: onOneTime,
        ),
        AppValueRow(
          icon: AppIcons.clock,
          title: 'remote.expires_24h'.tr(),
          subtitle: 'remote.expires_24h_subtitle'.tr(),
          chevron: false,
        ),
      ],
    ];
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (preset) ...[
          Row(
            children: [
              AppSvgIcon(AppIcons.fileDocument, size: 16, color: t.text2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  presetName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.secondary.copyWith(color: t.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'remote.create_link'.tr(),
            icon: AppIcons.send,
            size: AppButtonSize.large,
            onPressed: onPreset,
          ),
          const SizedBox(height: 10),
        ],
        AppButton(
          label: 'remote.choose_photo_video'.tr(),
          icon: AppIcons.image,
          size: AppButtonSize.large,
          variant: preset
              ? AppButtonVariant.secondary
              : AppButtonVariant.primary,
          onPressed: onMedia,
        ),
        const SizedBox(height: 10),
        AppButton(
          label: 'remote.choose_file'.tr(),
          icon: AppIcons.fileDocument,
          size: AppButtonSize.large,
          variant: AppButtonVariant.secondary,
          onPressed: onFile,
        ),
      ],
    );
    // An open iPhone Duo: the options on one side, choosing the file on the
    // other (split at the fold when half open). Elsewhere one column.
    if (context.isFoldableOpen) {
      final side = DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          border: BorderDirectional(start: BorderSide(color: t.line)),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppSvgIcon(
                      AppIcons.linkCopy,
                      size: 32,
                      color: t.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                actions,
              ],
            ),
          ),
        ),
      );
      final list = ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: options,
      );
      return FoldSplit(
        left: list,
        right: side,
        flat: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            Expanded(child: side),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ...options,
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
          child: actions,
        ),
      ],
    );
  }
}
