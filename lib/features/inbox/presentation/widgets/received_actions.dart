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

/// A received file: what to do with it first (open, share, more ways to
/// keep or pass it on), then where it came from and when, then delete.
Future<void> showReceivedDetail(BuildContext context, TransferRecord r) {
  final locale = context.locale.toLanguageTag();
  final when = DateFormat.yMMMd(locale).add_Hm().format(r.timestamp);
  final mime =
      r.fileType ?? lookupMimeType(r.fileName) ?? 'application/octet-stream';
  return showAppSheet<void>(
    context,
    title: shownName(r),
    subtitle: formatBytes(r.fileSize),
    leading: MediaThumb(path: r.savedPath, mime: mime, size: 48, radius: 12),
    builder: (ctx) {
      final t = ctx.tokens;
      final has = onDisk(r);
      void close() => Navigator.of(ctx).pop();
      final yes = 'history.yes'.tr(), no = 'history.no'.tr();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (has)
            AppSheetQuickRow(
              actions: [
                AppSheetQuick(
                  icon: AppIcons.eyePreview,
                  label: 'inbox.open'.tr(),
                  primary: true,
                  onTap: () {
                    close();
                    showFilePreview(
                      context,
                      path: r.savedPath!,
                      name: r.fileName,
                      mimeType: mime,
                      size: r.fileSize,
                    );
                  },
                ),
                AppSheetQuick(
                  icon: AppIcons.shareLink,
                  label: 'inbox.share'.tr(),
                  onTap: () => shareReceived([r]),
                ),
                AppSheetQuick(
                  icon: AppIcons.qrShare,
                  label: 'inbox.qr_short'.tr(),
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
              ],
            ),
          if (has && (InboxCubit.canSaveToPhotos && isMedia(r) || driveReady))
            AppSheetGroup(
              children: [
                if (InboxCubit.canSaveToPhotos && isMedia(r))
                  AppSheetAction(
                    icon: AppIcons.imageDown,
                    label: 'inbox.save_to_photos'.tr(),
                    onTap: () {
                      close();
                      savePhotos(context, [r]);
                    },
                  ),
                if (driveReady)
                  AppSheetAction(
                    icon: AppIcons.cloudSync,
                    label: 'vault.save_to_drive'.tr(),
                    onTap: () {
                      close();
                      saveToDrive(context, [r.savedPath!]);
                    },
                  ),
              ],
            ),
          AppSheetGroup(
            children: [
              AppSheetInfo('inbox.detail_from'.tr(), r.deviceAlias),
              if (shownName(r) != r.fileName)
                AppSheetInfo(
                  'inbox.detail_saved_as'.tr(),
                  r.fileName,
                  lines: 2,
                ),
              AppSheetInfo('inbox.detail_received'.tr(), when),
              AppSheetInfo(
                'inbox.detail_encrypted'.tr(),
                r.encrypted ? yes : no,
              ),
              AppSheetInfo('inbox.detail_verified'.tr(), r.verified ? yes : no),
            ],
          ),
          if (!has)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                'inbox.not_stored'.tr(),
                style: AppType.secondary.copyWith(color: t.danger),
              ),
            ),
          AppSheetGroup(
            children: [
              AppSheetAction(
                icon: AppIcons.trashDelete,
                label: 'inbox.delete'.tr(),
                destructive: true,
                onTap: () async {
                  close();
                  await deleteReceived(context, [r]);
                },
              ),
            ],
          ),
        ],
      );
    },
  );
}
