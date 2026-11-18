import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/telemetry/telemetry_service.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_photo_backup.dart';
import 'drive_format.dart';

/// The offer to back up this phone's photos, made once when a Drive is first
/// opened here with backup off (owner 2026-11-17: most Drives stayed empty
/// because the switch sat unseen above the gallery). Saying no is final for
/// the sheet; the line above the gallery keeps its "Turn on".
class DriveBackupOffer {
  const DriveBackupOffer._();

  /// Set once the sheet has been shown on this device.
  static const offeredKey = 'vault.backupOffered';

  /// Whether the sheet is due: a Drive ready on a phone with a photo library,
  /// backup off, and the offer not made here before.
  @visibleForTesting
  static bool due({
    required bool ready,
    required bool library,
    required bool on,
    required bool offered,
  }) => ready && library && !on && !offered;

  /// Show the sheet when it is due and turn backup on at a yes. [freeBytes]
  /// is the size of the Drive's plan, named as what backup costs: nothing.
  static Future<void> offer(
    BuildContext context, {
    required VaultPhotoBackup backup,
    required SharedPreferences prefs,
    required bool ready,
    required int? freeBytes,
    TelemetryService? telemetry,
  }) async {
    if (!due(
      ready: ready,
      library: backup.available,
      on: backup.on,
      offered: prefs.getBool(offeredKey) ?? false,
    )) {
      return;
    }
    await prefs.setBool(offeredKey, true);
    if (!context.mounted) return;
    telemetry?.recordCta('app_backup_offer', 'view');
    final yes = await showAppSheet<bool>(
      context,
      icon: AppIcons.cloudSync,
      title: 'vault.backup_offer_title'.tr(),
      subtitle: 'vault.backup_offer_sub'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Point(
            icon: AppIcons.passwordLock,
            text: 'vault.backup_offer_private'.tr(),
          ),
          _Point(icon: AppIcons.wifi, text: 'vault.backup_offer_wifi'.tr()),
          _Point(
            icon: AppIcons.cloudDone,
            text: freeBytes == null
                ? 'vault.backup_offer_free_plain'.tr()
                : 'vault.backup_offer_free'.tr(
                    namedArgs: {'size': decimalBytes(freeBytes)},
                  ),
          ),
          const SizedBox(height: 16),
          AppButton(
            label: 'vault.backup_offer_yes'.tr(),
            fullWidth: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'vault.backup_offer_later'.tr(),
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await backup.setOn(true);
    if (ok) {
      telemetry?.recordCta('app_backup_offer', 'click');
    } else if (context.mounted) {
      toast(context, 'vault.backup_access_denied'.tr(), type: ToastType.error);
    }
  }
}

/// One reason, as an icon and a line.
class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppSvgIcon(icon, size: 20, color: t.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: AppType.secondary.copyWith(color: t.text)),
          ),
        ],
      ),
    );
  }
}
