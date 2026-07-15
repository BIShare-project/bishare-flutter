import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../data/sync_engine.dart';

/// The pairing consent sheet (shown app-wide from the shell). The inviter's
/// HTTP exchange is held open while this is up — the engine auto-rejects after
/// its timeout, so a dismissed/ignored sheet declines safely.
Future<void> showSyncInviteSheet(
  BuildContext context,
  PendingSyncInvite invite,
) async {
  var decided = false;
  await showAppSheet<void>(
    context,
    title: 'sync.invite_title'.tr(),
    subtitle: 'sync.invite_message'.tr(namedArgs: {
      'device': invite.peerAlias.isEmpty ? '?' : invite.peerAlias,
      'folder': invite.rootName,
    }),
    icon: AppIcons.refreshSync,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Text(
            'sync.invite_explain'.tr(),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ShadTheme.of(sheetContext).colorScheme.mutedForeground,
            ),
          ),
        ),
        AppButton(
          label: 'sync.invite_accept'.tr(),
          icon: AppIcons.refreshSync,
          fullWidth: true,
          onPressed: () async {
            decided = true;
            Navigator.of(sheetContext).pop();
            // Default: <Documents>/BIShare Sync/<rootName> — one tap, no
            // picker, so the accept lands within the inviter's 30s window.
            final docs = await getApplicationDocumentsDirectory();
            final root = Directory(
              '${docs.path}${Platform.pathSeparator}BIShare Sync'
              '${Platform.pathSeparator}${invite.rootName}',
            );
            invite.accept(root.path);
          },
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'sync.invite_accept_custom'.tr(),
          variant: AppButtonVariant.outline,
          fullWidth: true,
          onPressed: () async {
            decided = true;
            Navigator.of(sheetContext).pop();
            final picked = await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'sync.pick_folder'.tr(),
            );
            if (picked == null || picked.isEmpty) {
              invite.reject();
            } else {
              invite.accept(picked);
            }
          },
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'sync.invite_decline'.tr(),
          variant: AppButtonVariant.ghost,
          fullWidth: true,
          onPressed: () {
            decided = true;
            Navigator.of(sheetContext).pop();
            invite.reject();
          },
        ),
        const SizedBox(height: 4),
      ],
    ),
  );
  // Swiped away / tapped outside — decline instead of leaving it hanging.
  if (!decided) invite.reject();
}
