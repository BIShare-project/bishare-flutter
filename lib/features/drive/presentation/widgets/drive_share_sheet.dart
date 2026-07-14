import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/ui/app_ui.dart';
import '../../data/drive_service.dart';
import '../../domain/drive_models.dart';
import '../drive_cubit.dart';

/// Create + present a share-link for a file (or folder): optional password and
/// expiry, then a scannable QR with copy / share / revoke — reusing the app's
/// [BiShareQr] and copy pattern.
Future<void> showDriveShareSheet(
  BuildContext context, {
  required DriveService service,
  required String name,
  String? fileId,
  String? folderId,
}) {
  return showGlassModal<void>(
    context,
    builder: (ctx) => _ShareSheet(
      service: service,
      name: name,
      fileId: fileId,
      folderId: folderId,
    ),
  );
}

/// Expiry choices in hours (0 = never).
const _expiryHours = [0, 1, 24, 168, 720];

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.service,
    required this.name,
    this.fileId,
    this.folderId,
  });

  final DriveService service;
  final String name;
  final String? fileId;
  final String? folderId;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _password = TextEditingController();
  int _expiry = 0;
  bool _busy = false;
  ShareLink? _link;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  String _expiryLabel(int h) => switch (h) {
    0 => 'drive.expiry_never'.tr(),
    1 => 'drive.expiry_1h'.tr(),
    24 => 'drive.expiry_24h'.tr(),
    168 => 'drive.expiry_7d'.tr(),
    _ => 'drive.expiry_30d'.tr(),
  };

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final link = await widget.service.createShare(
        fileId: widget.fileId,
        folderId: widget.folderId,
        password: _password.text.trim().isEmpty ? null : _password.text.trim(),
        expiresInHours: _expiry == 0 ? null : _expiry,
      );
      if (mounted) setState(() => _link = link);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, driveErrorKey(e).tr(), type: ToastType.error);
      }
    }
  }

  Future<void> _revoke() async {
    final link = _link;
    if (link == null) return;
    setState(() => _busy = true);
    try {
      await widget.service.revokeShare(link.id);
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'drive.link_revoked'.tr(), type: ToastType.success);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, driveErrorKey(e).tr(), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _link == null ? _options(context) : _result(context, _link!);
  }

  Widget _options(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: AppSvgIcon(AppIcons.shareLink, size: 28, color: cs.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'drive.create_link'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          const SizedBox(height: 20),
          Text(
            'drive.password_optional'.tr(),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          ShadInput(
            controller: _password,
            obscureText: true,
            placeholder: Text('drive.password_hint'.tr()),
          ),
          const SizedBox(height: 14),
          Text(
            'drive.expiry'.tr(),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 6),
          ShadSelect<int>(
            initialValue: _expiry,
            options: [
              for (final h in _expiryHours)
                ShadOption(value: h, child: Text(_expiryLabel(h))),
            ],
            selectedOptionBuilder: (context, value) => Text(_expiryLabel(value)),
            onChanged: (v) => setState(() => _expiry = v ?? 0),
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'drive.create_link'.tr(),
            icon: AppIcons.linkCopy,
            fullWidth: true,
            loading: _busy,
            onPressed: _create,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, ShareLink link) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BiShareQr(data: link.url),
          const SizedBox(height: 16),
          Text(
            widget.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'drive.share_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (link.hasPassword)
                AppBadge('drive.badge_password'.tr(), color: kAmber),
              if (link.expiresAt != null) AppBadge('drive.badge_expires'.tr()),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  size: ShadButtonSize.lg,
                  leading: const AppSvgIcon(AppIcons.copyDuplicate, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link.url));
                    if (context.mounted) {
                      toast(
                        context,
                        'common.link_copied'.tr(),
                        type: ToastType.success,
                      );
                    }
                  },
                  child: Text('common.copy'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  leading: const AppSvgIcon(AppIcons.shareLink, size: 18),
                  onPressed: () =>
                      SharePlus.instance.share(ShareParams(text: link.url)),
                  child: Text('common.share'.tr()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'drive.revoke_link'.tr(),
            icon: AppIcons.trashDelete,
            variant: AppButtonVariant.destructive,
            fullWidth: true,
            loading: _busy,
            onPressed: _revoke,
          ),
        ],
      ),
    );
  }
}
