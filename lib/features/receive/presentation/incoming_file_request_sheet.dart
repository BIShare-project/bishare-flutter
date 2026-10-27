import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/locator.dart';
import '../../../core/io/picked_mtime.dart';
import '../../../core/io/media_picker.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/ui/app_ui.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../send/data/transfer_client.dart';
import '../../send/domain/sendable_file.dart';

/// The reverse-flow prompt: another device is asking US for files. The user
/// picks photos/files and (on send) they're transferred back to the requester
/// via the normal path. Mirrors the native `IncomingFileRequestSheet`.
Future<void> showIncomingFileRequest(
  BuildContext context,
  PendingFileRequest pending,
) => showGlassModal<void>(
  context,
  builder: (ctx) => _RequestContent(pending: pending),
);

class _RequestContent extends StatefulWidget {
  const _RequestContent({required this.pending});
  final PendingFileRequest pending;

  @override
  State<_RequestContent> createState() => _RequestContentState();
}

class _RequestContentState extends State<_RequestContent> {
  final _uuid = const Uuid();
  final List<SendableFile> _selected = [];
  bool _sending = false;
  bool _done = false;
  bool _responded = false;

  @override
  void dispose() {
    // Catch-all: if the sheet is dismissed without an explicit choice, decline
    // (no-op if we already accepted). Frees the held connection on the peer.
    if (!_responded) widget.pending.respond(false);
    super.dispose();
  }

  Future<void> _pick({required bool photosOnly}) async {
    final List<String> paths;
    if (photosOnly) {
      paths = await pickMediaPaths();
    } else {
      paths = await pickFilePaths();
    }
    final files = [
      for (final p in paths) SendableFile.fromPath(p, id: _uuid.v4()),
    ];
    if (files.isNotEmpty) setState(() => _selected.addAll(files));
  }

  Future<void> _send() async {
    if (_selected.isEmpty) return;
    _responded = true;
    widget.pending.respond(true);
    setState(() => _sending = true);

    final r = widget.pending.request;
    final device = DiscoveredDevice(
      fingerprint: r.requesterFingerprint,
      alias: r.requesterAlias,
      host: r.requesterHost,
      port: r.requesterPort,
      lastSeen: DateTime.now(),
      firstSeen: DateTime.now(),
    );
    try {
      await getIt<TransferClient>().send(_selected, device);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _done = true;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      toast(
        context,
        'receive.failed_to_send'.tr(namedArgs: {'alias': r.requesterAlias}),
        type: ToastType.error,
      );
    }
  }

  void _decline() {
    _responded = true;
    widget.pending.respond(false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = widget.pending.request;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: AppIconButton(
              icon: AppIcons.close,
              color: t.text2,
              tooltip: 'receive.decline'.tr(),
              onPressed: _decline,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.accentSoft,
                  ),
                  child: AppSvgIcon(
                    AppIcons.uploadFile,
                    size: 32,
                    color: t.accent,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'receive.requesting_files'.tr(
                    namedArgs: {'alias': r.requesterAlias},
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sheetTitle.copyWith(color: t.text),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                r.message?.isNotEmpty == true
                    ? '"${r.message}"'
                    : 'receive.request_hint'.tr(),
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: t.text2),
              ),
              const SizedBox(height: 18),
              if (_done)
                _status(
                  t,
                  AppIcons.successSent,
                  t.ok,
                  'receive.files_sent'.tr(),
                )
              else if (_sending)
                _status(
                  t,
                  null,
                  t.accent,
                  'receive.sending_n_files'.plural(_selected.length),
                )
              else
                _picker(t),
            ],
          ),
        ),
      ],
    );
  }

  Widget _picker(AppTokens t) {
    final shown = _selected.take(5).toList();
    final more = _selected.length - shown.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'receive.choose_photos'.tr(),
                icon: AppIcons.image,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.large,
                onPressed: () => _pick(photosOnly: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: 'receive.choose_files'.tr(),
                icon: AppIcons.fileDocument,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.large,
                onPressed: () => _pick(photosOnly: false),
              ),
            ),
          ],
        ),
        if (_selected.isNotEmpty) ...[
          AppSectionHeader('receive.n_files_selected'.plural(_selected.length)),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const AppRowDivider(indent: 52),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.sunken,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AppSvgIcon(
                      fileIcon(shown[i].mimeType),
                      size: 20,
                      color: t.text2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      shown[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row.copyWith(color: t.text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatBytes(shown[i].size),
                    style: AppType.secondary.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
          ],
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'receive.more_count'.tr(namedArgs: {'count': '$more'}),
                style: AppType.secondary.copyWith(color: t.text2),
              ),
            ),
        ],
        const SizedBox(height: 16),
        if (_selected.isEmpty)
          AppButton(
            label: 'receive.decline'.tr(),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.large,
            fullWidth: true,
            onPressed: _decline,
          )
        else
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'receive.decline'.tr(),
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.large,
                  onPressed: _decline,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'receive.send_n_files'.plural(_selected.length),
                  size: AppButtonSize.large,
                  onPressed: _send,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _status(AppTokens t, String? icon, Color tint, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: icon == null
                ? Center(
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: tint,
                      ),
                    ),
                  )
                : AppSvgIcon(icon, size: 52, color: tint),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.pageTitle.copyWith(color: t.text),
          ),
        ],
      ),
    );
  }
}
