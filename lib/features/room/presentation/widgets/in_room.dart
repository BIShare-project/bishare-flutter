import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/identity/device_identity.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../remote/data/cloud_transfer_service.dart' show describeDownloadError;
import '../../domain/room_models.dart';
import '../room_cubit.dart';
import 'add_files_bar.dart';
import 'members_row.dart';
import 'room_file_row.dart';
import 'room_header_card.dart';
import 'room_top_bar.dart';

class InRoom extends StatelessWidget {
  const InRoom({super.key, required this.state});
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final session = state.session!;
    return AppResponsivePane(
      maxWidth: 640,
      child: Column(
        children: [
          RoomTopBar(session: session),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                RoomHeaderCard(state: state),
                const SizedBox(height: 16),
                MembersRow(members: state.members),
                const SizedBox(height: 16),
                AddFilesBar(onPicked: (files) => _add(context, files)),
                if (state.uploadingLabel != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(cs.primary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'room.uploading'.tr(namedArgs: {'label': '${state.uploadingLabel}'}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.mutedForeground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'room.shared_files'.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.mutedForeground,
                  ),
                ),
                const SizedBox(height: 8),
                if (state.files.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'room.no_files'.tr(),
                        style: TextStyle(color: cs.mutedForeground),
                      ),
                    ),
                  )
                else
                  for (final f in state.files)
                    RoomFileRow(
                      file: f,
                      isMine:
                          f.ownerFingerprint == getIt<DeviceIdentity>().fingerprint,
                      onDownload: () => _download(context, f),
                      onOpen: () => _open(context, f),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, List<String> paths) async {
    final cubit = context.read<RoomCubit>();
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final name = file.uri.pathSegments.last;
      try {
        await cubit.addFile(
          file,
          name: name,
          mime: lookupMimeType(name) ?? 'application/octet-stream',
        );
      } on Object catch (e) {
        if (context.mounted) {
          toast(
              context,
              'room.failed_to_add'.tr(namedArgs: {
                'name': name,
                'error': describeDownloadError(e),
              }),
              type: ToastType.error);
        }
      }
    }
  }

  Future<void> _download(BuildContext context, RoomFile f) async {
    final cubit = context.read<RoomCubit>();
    toast(context, 'room.downloading'.tr(namedArgs: {'name': f.fileName}));
    try {
      await cubit.download(f);
      if (context.mounted) {
        toast(context, 'room.saved'.tr(namedArgs: {'name': f.fileName}),
            type: ToastType.success);
      }
    } on Object catch (e) {
      if (context.mounted) {
        toast(context, describeDownloadError(e), type: ToastType.error);
      }
    }
  }

  /// Tap a file → fetch it to a temp path and open the rich preview.
  Future<void> _open(BuildContext context, RoomFile f) async {
    final cubit = context.read<RoomCubit>();
    toast(context, 'room.opening'.tr(namedArgs: {'name': f.fileName}));
    try {
      final file = await cubit.downloadTemp(f);
      if (context.mounted) {
        await showFilePreview(
          context,
          path: file.path,
          name: f.fileName,
          mimeType: f.fileType,
          size: f.size,
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        toast(context, describeDownloadError(e), type: ToastType.error);
      }
    }
  }
}
