import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../instant_share/presentation/instant_share_sheet.dart';
import '../../../vault/presentation/drive/drive_actions.dart';
import '../../domain/inbox_groups.dart';
import '../inbox_cubit.dart';

/// What can be done with received files, the same from a row, a tile, the
/// action bar and the photo viewer.

bool onDisk(TransferRecord r) =>
    r.savedPath != null && File(r.savedPath!).existsSync();

/// A photo opens the swipeable viewer; any other file its detail sheet.
void openReceived(BuildContext context, TransferRecord r) {
  if (isImage(r)) {
    final images = context.read<InboxCubit>().state.where(isImage).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final start = images.indexWhere((x) => x.id == r.id);
    context.push(
      '/gallery',
      extra: (images: images, startIndex: start < 0 ? 0 : start),
    );
    return;
  }
  showReceivedDetail(context, r);
}

Future<void> shareReceived(List<TransferRecord> records) async {
  final files = [
    for (final r in records)
      if (onDisk(r)) XFile(r.savedPath!),
  ];
  if (files.isEmpty) return;
  await SharePlus.instance.share(ShareParams(files: files));
}

/// Saves the photos and videos among [records] to the gallery and says how
/// many went in.
Future<void> savePhotos(
  BuildContext context,
  List<TransferRecord> records,
) async {
  final n = await context.read<InboxCubit>().saveAllMedia(records);
  if (!context.mounted) return;
  toast(
    context,
    n > 0
        ? 'inbox.saved_n_to_photos'.tr(namedArgs: {'count': '$n'})
        : 'inbox.could_not_save'.tr(),
    type: n > 0 ? ToastType.success : ToastType.error,
  );
}

/// Asks, then deletes [records] from this device and from the history.
/// True when they were deleted.
Future<bool> deleteReceived(
  BuildContext context,
  List<TransferRecord> records,
) async {
  final cubit = context.read<InboxCubit>();
  final yes = await showAppConfirm(
    context,
    title: 'inbox.delete_n_title'.plural(records.length),
    message: 'inbox.delete_body'.tr(),
    confirmLabel: 'inbox.delete'.tr(),
  );
  if (!yes) return false;
  await cubit.deleteMany(records);
  return true;
}

/// A received file: where it came from, when, and what to do with it.
Future<void> showReceivedDetail(BuildContext context, TransferRecord r) {
  final locale = context.locale.toLanguageTag();
  final when = DateFormat.yMMMd(locale).add_Hm().format(r.timestamp);
  return showAppSheet<void>(
    context,
    title: shownName(r),
    subtitle: formatBytes(r.fileSize),
    builder: (ctx) {
      final t = ctx.tokens;
      final has = onDisk(r);
      void close() => Navigator.of(ctx).pop();
      Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(k, style: AppType.body.copyWith(color: t.text2)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                v,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body.copyWith(
                  color: t.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
      final yes = 'history.yes'.tr(), no = 'history.no'.tr();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          kv('inbox.detail_from'.tr(), r.deviceAlias),
          if (shownName(r) != r.fileName)
            kv('inbox.detail_saved_as'.tr(), r.fileName),
          kv('inbox.detail_received'.tr(), when),
          kv('inbox.detail_encrypted'.tr(), r.encrypted ? yes : no),
          kv('inbox.detail_verified'.tr(), r.verified ? yes : no),
          if (!has)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'inbox.not_stored'.tr(),
                style: AppType.secondary.copyWith(color: t.danger),
              ),
            ),
          const SizedBox(height: 14),
          if (has)
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'inbox.share'.tr(),
                    icon: AppIcons.shareLink,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.large,
                    onPressed: () => shareReceived([r]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'inbox.open'.tr(),
                    size: AppButtonSize.large,
                    onPressed: () {
                      close();
                      showFilePreview(
                        context,
                        path: r.savedPath!,
                        name: r.fileName,
                        mimeType:
                            r.fileType ??
                            lookupMimeType(r.fileName) ??
                            'application/octet-stream',
                        size: r.fileSize,
                      );
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 6),
          if (has && InboxCubit.canSaveToPhotos && isMedia(r))
            AppValueRow(
              icon: AppIcons.imageDown,
              title: 'inbox.save_to_photos'.tr(),
              chevron: false,
              onTap: () {
                close();
                savePhotos(context, [r]);
              },
            ),
          if (has && driveReady)
            AppValueRow(
              icon: AppIcons.cloudSync,
              title: 'vault.save_to_drive'.tr(),
              chevron: false,
              onTap: () {
                close();
                saveToDrive(context, [r.savedPath!]);
              },
            ),
          if (has)
            AppValueRow(
              icon: AppIcons.qrShare,
              title: 'inbox.share_via_qr'.tr(),
              chevron: false,
              onTap: () {
                close();
                showInstantShare(
                  context,
                  path: r.savedPath!,
                  fileName: r.fileName,
                  mimeType: r.fileType ?? 'application/octet-stream',
                );
              },
            ),
          AppValueRow(
            icon: AppIcons.trashDelete,
            title: 'inbox.delete'.tr(),
            destructive: true,
            chevron: false,
            onTap: () async {
              close();
              await deleteReceived(context, [r]);
            },
          ),
        ],
      );
    },
  );
}
