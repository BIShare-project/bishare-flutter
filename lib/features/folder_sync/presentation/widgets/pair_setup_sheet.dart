import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/server/transfer_server.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../discovery/data/discovery_service.dart';
import '../../data/sync_engine.dart';
import '../folder_sync_cubit.dart';

/// The two-step "new sync pair" flow in one sheet: pick a local folder, then an
/// ONLINE device, then send the pairing invite (consent happens on the peer).
///
/// Desktop offers a free directory picker. iOS/Android use the app's BIShare
/// folder (the save location — visible in the Files app): a picker-chosen
/// folder there is security-scoped/SAF and NOT readable via dart:io, so the
/// scanner would silently see 0 files (§4.2 — scoped-bookmark access is the
/// planned follow-up; the app folder is the honest v1).
Future<void> showPairSetupSheet(
  BuildContext context,
  FolderSyncCubit cubit,
) async {
  final String? rootPath;
  if (Platform.isIOS || Platform.isAndroid) {
    rootPath = getIt<TransferServer>().saveDirectory.path;
  } else {
    // Step 1 — folder (native directory picker; returns null on cancel).
    rootPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'sync.pick_folder'.tr(),
    );
  }
  if (rootPath == null || rootPath.isEmpty) return;
  if (!context.mounted) return;
  // A non-nullable copy: closure capture below blocks type promotion.
  final root = rootPath;

  // Step 2 — an online device.
  await showAppSheet<void>(
    context,
    title: 'sync.pick_device'.tr(),
    subtitle: root,
    icon: AppIcons.refreshSync,
    builder: (sheetContext) => _DevicePickList(
      onPicked: (fingerprint) async {
        Navigator.of(sheetContext).pop();
        final outcome = await cubit.createPair(
          peerFingerprint: fingerprint,
          rootPath: root,
        );
        if (!context.mounted) return;
        switch (outcome) {
          case PairInviteOutcome.accepted:
            toast(context, 'sync.pair_created'.tr(), type: ToastType.success);
          case PairInviteOutcome.rejected:
            toast(context, 'sync.error_declined'.tr(), type: ToastType.error);
          case null:
            toast(
              context,
              (cubit.state.errorKey ?? 'sync.error_invite_failed').tr(),
              type: ToastType.error,
            );
        }
      },
    ),
  );
}

class _DevicePickList extends StatelessWidget {
  const _DevicePickList({required this.onPicked});

  final void Function(String fingerprint) onPicked;

  @override
  Widget build(BuildContext context) {
    final devices = getIt<DiscoveryService>().current;
    if (devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppEmptyState(
          icon: AppIcons.refreshSync,
          title: 'sync.no_devices_title'.tr(),
          message: 'sync.no_devices_message'.tr(),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final d in devices)
          AppListTile(
            leading: const AppSvgIcon(AppIcons.refreshSync, size: 18),
            title: Text(d.alias, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${d.deviceModel} · ${d.host}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => onPicked(d.fingerprint),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
