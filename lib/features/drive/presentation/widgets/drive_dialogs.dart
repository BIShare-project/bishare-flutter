import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../../remote/data/cloud_transfer_service.dart';
import '../../../remote/presentation/remote_download.dart';
import '../../data/drive_service.dart';
import '../../domain/drive_models.dart';
import '../drive_cubit.dart';

/// A single-field name prompt (create folder / rename), styled like Settings'
/// text prompts. Returns the trimmed text, or null if dismissed.
Future<String?> promptName(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String icon,
  required String hint,
  required String buttonLabel,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showAppSheet<String>(
    context,
    icon: icon,
    title: title,
    subtitle: subtitle,
    builder: (ctx) {
      void submit() {
        final text = controller.text.trim();
        if (text.isNotEmpty) Navigator.pop(ctx, text);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadInput(
            controller: controller,
            autofocus: true,
            placeholder: Text(hint),
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 14),
          AppButton(label: buttonLabel, fullWidth: true, onPressed: submit),
        ],
      );
    },
  );
}

/// A destructive confirmation sheet. Returns true if confirmed.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String confirmLabel,
}) async {
  final cs = ShadTheme.of(context).colorScheme;
  final res = await showAppSheet<bool>(
    context,
    icon: AppIcons.trashDelete,
    iconColor: cs.destructive,
    title: title,
    subtitle: subtitle,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetAction(
          icon: AppIcons.trashDelete,
          label: confirmLabel,
          destructive: true,
          onTap: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return res == true;
}

/// Resolve a presigned URL for [file] and stream it into the app's save
/// directory + Inbox behind the shared download-progress modal — reusing
/// `CloudTransferService`'s save/record infra. Drive errors are surfaced as a
/// clean localized message (not a raw exception) inside the modal.
Future<void> downloadDriveFile(
  BuildContext context, {
  required DriveService service,
  required CloudTransferService cloud,
  required DriveFile file,
}) {
  return showRemoteDownload(
    context,
    label: file.name,
    run: (onProgress, cancel) async {
      String url;
      try {
        url = await service.downloadUrl(file.id);
      } on Object catch (e) {
        throw CloudDownloadException(driveErrorKey(e).tr());
      }
      return cloud.downloadDirect(
        Uri.parse(url),
        onProgress: onProgress,
        cancel: cancel,
        senderLabel: 'drive.source_label'.tr(),
      );
    },
  );
}
