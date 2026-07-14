import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../data/drive_service.dart';
import '../domain/drive_models.dart';
import 'drive_cubit.dart';
import 'widgets/drive_dialogs.dart';

/// Share links — list every active link with copy + revoke. Empty shows an
/// [AppEmptyState]. Self-contained: loads on open and after each action.
class SharesPage extends StatefulWidget {
  const SharesPage({super.key});

  @override
  State<SharesPage> createState() => _SharesPageState();
}

class _SharesPageState extends State<SharesPage> {
  DriveService get _service => getIt<DriveService>();

  List<ShareLink> _links = const [];
  bool _loading = true;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final links = await _service.shares();
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
        _errorKey = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = driveErrorKey(e);
      });
    }
  }

  Future<void> _copy(ShareLink link) async {
    await Clipboard.setData(ClipboardData(text: link.url));
    if (mounted) {
      toast(context, 'common.link_copied'.tr(), type: ToastType.success);
    }
  }

  Future<void> _revoke(ShareLink link) async {
    final ok = await confirmDestructive(
      context,
      title: 'drive.revoke_title'.tr(),
      subtitle: 'drive.revoke_message'.tr(),
      confirmLabel: 'drive.revoke_link'.tr(),
    );
    if (!ok) return;
    try {
      await _service.revokeShare(link.id);
      if (!mounted) return;
      toast(context, 'drive.link_revoked'.tr(), type: ToastType.success);
      await _load();
    } on Object catch (e) {
      if (mounted) toast(context, driveErrorKey(e).tr(), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 760,
          child: Column(
            children: [
              AppScreenHeader(
                title: 'drive.manage_links'.tr(),
                subtitle: _links.isEmpty
                    ? null
                    : 'drive.links_count'.plural(_links.length),
                onBack: () => context.pop(),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_links.isEmpty) {
      return AppEmptyState(
        icon: AppIcons.linkCopy,
        title: _errorKey != null
            ? 'drive.load_error_title'.tr()
            : 'drive.no_links_title'.tr(),
        message: _errorKey != null
            ? _errorKey!.tr()
            : 'drive.no_links_message'.tr(),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 6, bottom: 28),
        children: [
          AppGroup(
            child: Column(
              children: [
                for (var i = 0; i < _links.length; i++) ...[
                  if (i > 0) const AppRowDivider(indent: 62),
                  _ShareRow(
                    link: _links[i],
                    onCopy: () => _copy(_links[i]),
                    onRevoke: () => _revoke(_links[i]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.link,
    required this.onCopy,
    required this.onRevoke,
  });

  final ShareLink link;
  final VoidCallback onCopy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final title = link.folderId != null
        ? 'drive.folder_link'.tr()
        : 'drive.file_link'.tr();
    return AppRowMenu(
      title: title,
      subtitle: link.url,
      actions: [
        AppMenuAction(
          icon: AppIcons.copyDuplicate,
          label: 'common.copy'.tr(),
          onTap: onCopy,
        ),
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'drive.revoke_link'.tr(),
          destructive: true,
          onTap: onRevoke,
        ),
      ],
      child: AppListTile(
        leading: AppSvgIcon(AppIcons.shareLink, size: 30, color: cs.primary),
        title: Text(title),
        subtitle: Text(
          link.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (link.hasPassword)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AppSvgIcon(
                  AppIcons.passwordLock,
                  size: 16,
                  color: cs.mutedForeground,
                ),
              ),
            AppBadge('↓ ${link.downloadCount}'),
          ],
        ),
        onTap: onCopy,
      ),
    );
  }
}
