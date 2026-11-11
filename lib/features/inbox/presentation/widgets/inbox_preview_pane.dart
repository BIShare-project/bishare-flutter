import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';

import '../../../../core/storage/app_database.dart';
import '../../../../core/ui/app_ui.dart';
import '../../domain/inbox_groups.dart';
import '../inbox_cubit.dart';
import 'received_actions.dart';

/// The received file shown beside the Inbox on an open iPhone Duo. While this
/// scope is above the Inbox, tapping a file selects it here instead of
/// opening the gallery or the detail sheet (see [openReceived]).
class InboxPreviewScope extends InheritedNotifier<ValueNotifier<int?>> {
  const InboxPreviewScope({
    super.key,
    required ValueNotifier<int?> selected,
    required super.child,
  }) : super(notifier: selected);

  /// The selection of the nearest scope, or null on a phone, an iPad, a
  /// computer (no scope there, so files open as they always have).
  static ValueNotifier<int?>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InboxPreviewScope>()?.notifier;
}

/// The preview side of the Inbox: the chosen file large, its name, and the
/// same actions and details as the detail sheet, with a close button. Shown
/// only while a file is chosen; a file that is gone (deleted) closes it.
class InboxPreviewPane extends StatelessWidget {
  const InboxPreviewPane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selected = InboxPreviewScope.maybeOf(context);
    final records = context.watch<InboxCubit>().state;
    final r = records.where((x) => x.id == selected?.value).firstOrNull;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: BorderDirectional(start: BorderSide(color: t.line)),
      ),
      child: r == null
          ? const SizedBox.shrink()
          : ListView(
              key: ValueKey(r.id),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppIconButton(
                    icon: AppIcons.close,
                    tooltip: 'send.close'.tr(),
                    onPressed: () => selected?.value = null,
                  ),
                ),
                _Hero(record: r),
                const SizedBox(height: 14),
                Text(
                  shownName(r),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.title.copyWith(color: t.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatBytes(r.fileSize)} · ${r.deviceAlias}',
                  style: AppType.secondary.copyWith(color: t.text2),
                ),
                const SizedBox(height: 12),
                ReceivedDetailBody(record: r, onDone: () {}),
              ],
            ),
    );
  }
}

/// The file large: a photo as it is, anything else as its thumbnail. Tap to
/// open it full screen.
class _Hero extends StatelessWidget {
  const _Hero({required this.record});

  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = record;
    final mime =
        r.fileType ?? lookupMimeType(r.fileName) ?? 'application/octet-stream';
    final path = onDisk(r) ? r.savedPath : null;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: t.sunken,
          child: InkWell(
            onTap: path == null
                ? null
                : () => showFilePreview(
                    context,
                    path: path,
                    name: r.fileName,
                    mimeType: mime,
                    size: r.fileSize,
                  ),
            child: LayoutBuilder(
              builder: (context, box) {
                if (path != null && isImage(r)) {
                  return Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    cacheWidth:
                        (box.maxWidth * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    errorBuilder: (_, _, _) => _thumb(path, mime),
                  );
                }
                return _thumb(path, mime);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(String? path, String mime) => Center(
    child: MediaThumb(path: path, mime: mime, size: 96, radius: 18),
  );
}
