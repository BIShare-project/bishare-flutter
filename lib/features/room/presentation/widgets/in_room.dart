import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/identity/device_identity.dart';
import '../../../../core/io/media_picker.dart';
import '../../../../core/io/picked_mtime.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../remote/data/cloud_transfer_service.dart'
    show describeDownloadError;
import '../../domain/room_models.dart';
import '../room_cubit.dart';
import 'room_file_row.dart';

/// Inside a room (redesign-plan.md 7.3): the code to share (copy, and a QR
/// for a room on the internet), whether files are end-to-end encrypted,
/// who is here, adding photos or files, and the shared files. Leaving asks
/// first.
class InRoom extends StatelessWidget {
  const InRoom({super.key, required this.state});
  final RoomState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final session = state.session!;
    final me = getIt<DeviceIdentity>().fingerprint;
    return Column(
      children: [
        AppScreenHeader(
          title: 'room.title'.tr(),
          subtitle: [
            session.remote ? 'room.remote'.tr() : 'room.local'.tr(),
            session.isHost ? 'room.host'.tr() : 'room.member'.tr(),
            'room.n_connected'.tr(
              namedArgs: {'count': '${state.members.length}'},
            ),
          ].join(' · '),
          actions: [
            TextButton(
              onPressed: () => _leave(context),
              style: TextButton.styleFrom(foregroundColor: t.danger),
              child: Text('room.leave'.tr()),
            ),
            const SizedBox(width: 6),
          ],
        ),
        Expanded(
          child: AppResponsivePane(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                _CodeCard(session: session, security: state.security),
                if (state.members.isNotEmpty) ...[
                  AppSectionHeader('room.members'.tr()),
                  _Members(members: state.members),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'room.photos'.tr(),
                          icon: AppIcons.image,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => _pick(context, media: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          label: 'room.files'.tr(),
                          icon: AppIcons.folder,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => _pick(context, media: false),
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.uploadingLabel != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'room.uploading'.tr(
                              namedArgs: {'label': '${state.uploadingLabel}'},
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.secondary.copyWith(color: t.text2),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                AppSectionHeader('room.shared_files'.tr()),
                if (state.files.isEmpty)
                  AppEmptyState(
                    icon: AppIcons.folderOpen,
                    title: 'room.no_files'.tr(),
                    message: 'room.no_files_hint'.tr(),
                  )
                else
                  for (var i = 0; i < state.files.length; i++) ...[
                    if (i > 0) const AppRowDivider(indent: 70),
                    RoomFileRow(
                      file: state.files[i],
                      isMine: state.files[i].ownerFingerprint == me,
                      onDownload: () => _download(context, state.files[i]),
                      onOpen: () => _open(context, state.files[i]),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _leave(BuildContext context) async {
    final cubit = context.read<RoomCubit>();
    final yes = await showAppConfirm(
      context,
      title: 'room.leave_title'.tr(),
      message: 'room.leave_body'.tr(),
      confirmLabel: 'room.leave'.tr(),
    );
    if (yes) await cubit.leave();
  }

  Future<void> _pick(BuildContext context, {required bool media}) async {
    final paths = media ? await pickMediaPaths() : await pickFilePaths();
    if (paths.isNotEmpty && context.mounted) await _add(context, paths);
  }

  /// An encrypted room's files can't be sealed or opened before a member has
  /// handed this device the room key.
  bool _keyPending(BuildContext context, {RoomFile? file}) {
    if (state.security != RoomSecurity.waitingForKey &&
        !(file?.isSealed ?? false)) {
      return false;
    }
    toast(context, 'room.e2e_waiting'.tr());
    return true;
  }

  Future<void> _add(BuildContext context, List<String> paths) async {
    if (_keyPending(context)) return;
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
            'room.failed_to_add'.tr(
              namedArgs: {'name': name, 'error': describeDownloadError(e)},
            ),
            type: ToastType.error,
          );
        }
      }
    }
  }

  Future<void> _download(BuildContext context, RoomFile f) async {
    if (_keyPending(context, file: f)) return;
    final cubit = context.read<RoomCubit>();
    toast(context, 'room.downloading'.tr(namedArgs: {'name': f.fileName}));
    try {
      await cubit.download(f);
      if (context.mounted) {
        toast(
          context,
          'room.saved'.tr(namedArgs: {'name': f.fileName}),
          type: ToastType.success,
        );
      }
    } on Object catch (e) {
      if (context.mounted) {
        toast(context, describeDownloadError(e), type: ToastType.error);
      }
    }
  }

  /// Tap a file: fetch it to a temp path and open the preview.
  Future<void> _open(BuildContext context, RoomFile f) async {
    if (_keyPending(context, file: f)) return;
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

/// The code others type to join, big and spaced, with Copy and (for a room
/// on the internet, which a browser can join) a QR; under it, whether the
/// files are end-to-end encrypted.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.session, required this.security});

  final RoomSession session;
  final RoomSecurity security;

  /// The browser page that joins this room; only internet rooms have one.
  String? get _webLink => session.remote
      ? 'https://bishare.app/rooms?code=${session.code}'
      : null;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final link = _webLink;
    return AppCard(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'room.code_label'.tr(),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  session.code,
                  style: AppType.title.copyWith(
                    color: t.text,
                    letterSpacing: 6,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              AppIconButton(
                icon: AppIcons.copyDuplicate,
                tooltip: 'common.copy'.tr(),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: session.code));
                  if (context.mounted) {
                    toast(
                      context,
                      'room.code_copied'.tr(),
                      type: ToastType.success,
                    );
                  }
                },
              ),
              if (link != null)
                AppIconButton(
                  icon: AppIcons.qrShare,
                  tooltip: 'room.show_qr'.tr(),
                  onPressed: () => showAppSheet<void>(
                    context,
                    icon: AppIcons.qrShare,
                    title: session.code,
                    subtitle: 'room.qr_hint'.tr(),
                    builder: (_) => Center(child: BiShareQr(data: link)),
                  ),
                ),
            ],
          ),
          if (security != RoomSecurity.unknown) ...[
            const SizedBox(height: 10),
            _SecurityLine(security: security),
          ],
        ],
      ),
    );
  }
}

/// Whether the room's files are end-to-end encrypted on this device.
class _SecurityLine extends StatelessWidget {
  const _SecurityLine({required this.security});
  final RoomSecurity security;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (Widget icon, String text, Color color) = switch (security) {
      RoomSecurity.encrypted => (
        AppSvgIcon(AppIcons.passwordLock, size: 15, color: t.ok),
        'room.e2e_on'.tr(),
        t.ok,
      ),
      RoomSecurity.waitingForKey => (
        SizedBox.square(
          dimension: 13,
          child: CircularProgressIndicator(strokeWidth: 1.8, color: t.text2),
        ),
        'room.e2e_waiting'.tr(),
        t.text2,
      ),
      _ => (
        AppSvgIcon(AppIcons.circleAlert, size: 15, color: t.warn),
        'room.e2e_off'.tr(),
        t.warn,
      ),
    };
    return Row(
      children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.secondary.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Who is in the room: a round device icon and the name, side by side.
class _Members extends StatelessWidget {
  const _Members({required this.members});
  final List<RoomMember> members;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: members.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 64,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: AppSvgIcon(
                  iconForDevice(members[i].deviceType),
                  size: 21,
                  color: t.accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                members[i].alias,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppType.small.copyWith(color: t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
