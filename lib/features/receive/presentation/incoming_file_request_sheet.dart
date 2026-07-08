import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/locator.dart';
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
    final res = await FilePicker.platform.pickFiles(
      type: photosOnly ? FileType.media : FileType.any,
      allowMultiple: true,
    );
    if (res == null) return;
    final files = res.files
        .where((f) => f.path != null)
        .map((f) => SendableFile.fromPath(f.path!, id: _uuid.v4()))
        .toList();
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
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(cs),
          const SizedBox(height: 18),
          if (_done)
            _status(cs, AppIcons.successSent, kOnlineGreen, 'receive.files_sent'.tr())
          else if (_sending)
            _status(
              cs,
              null,
              cs.primary,
              'receive.sending_n_files'.plural(_selected.length),
            )
          else
            _picker(cs),
        ],
      ),
    );
  }

  // ---- Header ----

  Widget _header(ShadColorScheme cs) {
    final r = widget.pending.request;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: AppSvgIcon(AppIcons.uploadFile, size: 32, color: cs.primary),
        ),
        const SizedBox(height: 14),
        Text(
          'receive.requesting_files'.tr(namedArgs: {'alias': r.requesterAlias}),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.foreground,
          ),
        ),
        if (r.message?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(
            '"${r.message}"',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: cs.mutedForeground,
            ),
          ),
        ],
      ],
    );
  }

  // ---- Picker + selected + actions ----

  Widget _picker(ShadColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _optionRow(
          cs,
          icon: AppIcons.image,
          label: 'receive.choose_photos'.tr(),
          tint: cs.primary,
          onTap: () => _pick(photosOnly: true),
        ),
        const SizedBox(height: 10),
        _optionRow(
          cs,
          icon: AppIcons.folder,
          label: 'receive.choose_files'.tr(),
          tint: Colors.orange,
          onTap: () => _pick(photosOnly: false),
        ),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 14),
          _selectedCard(cs),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.lg,
                onPressed: _decline,
                child: Text('receive.decline'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ShadButton(
                size: ShadButtonSize.lg,
                enabled: _selected.isNotEmpty,
                onPressed: _send,
                leading: const AppSvgIcon(AppIcons.send, size: 18),
                child: Text(
                  _selected.isEmpty
                      ? 'receive.send_files'.tr()
                      : 'receive.send_n_files'.plural(_selected.length),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _optionRow(
    ShadColorScheme cs, {
    required String icon,
    required String label,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: cs.muted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11),
              ),
              child: AppSvgIcon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.foreground,
                ),
              ),
            ),
            AppSvgIcon(
              AppIcons.chevronRight,
              size: 18,
              color: cs.mutedForeground.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectedCard(ShadColorScheme cs) {
    final shown = _selected.take(5).toList();
    final more = _selected.length - shown.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'receive.n_files_selected'.plural(_selected.length),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 8),
          for (final f in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  AppSvgIcon(fileIcon(f.mimeType), size: 15, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: cs.foreground),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatBytes(f.size),
                    style: TextStyle(fontSize: 11.5, color: cs.mutedForeground),
                  ),
                ],
              ),
            ),
          if (more > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'receive.more_count'.tr(namedArgs: {'count': '$more'}),
                style: TextStyle(fontSize: 12.5, color: cs.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }

  Widget _status(
    ShadColorScheme cs,
    String? icon,
    Color tint,
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: icon == null
                ? Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3, color: tint),
                    ),
                  )
                : AppSvgIcon(icon, size: 60, color: tint),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
        ],
      ),
    );
  }
}
