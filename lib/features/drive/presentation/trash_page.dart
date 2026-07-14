import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../data/drive_service.dart';
import '../domain/drive_models.dart';
import 'drive_cubit.dart';
import 'widgets/drive_dialogs.dart';

/// Trash — soft-deleted files with restore + permanent-delete. Empty shows an
/// [AppEmptyState]. Self-contained (no app-wide cubit): loads on open and after
/// each action.
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  DriveService get _service => getIt<DriveService>();

  List<DriveFile> _files = const [];
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
      final page = await _service.trash(perPage: 100);
      if (!mounted) return;
      setState(() {
        _files = page.files;
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

  Future<void> _restore(DriveFile file) async {
    try {
      await _service.restoreFile(file.id);
      if (!mounted) return;
      toast(context, 'drive.restored'.tr(), type: ToastType.success);
      await _load();
    } on Object catch (e) {
      if (mounted) toast(context, driveErrorKey(e).tr(), type: ToastType.error);
    }
  }

  Future<void> _deleteForever(DriveFile file) async {
    final ok = await confirmDestructive(
      context,
      title: 'drive.delete_forever_title'.tr(),
      subtitle: 'drive.delete_forever_message'.tr(
        namedArgs: {'name': file.name},
      ),
      confirmLabel: 'drive.delete_forever_confirm'.tr(),
    );
    if (!ok) return;
    try {
      await _service.deleteFilePermanent(file.id);
      if (!mounted) return;
      toast(context, 'drive.deleted_forever'.tr(), type: ToastType.success);
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
                title: 'drive.trash'.tr(),
                subtitle: _files.isEmpty
                    ? null
                    : 'drive.trash_count'.plural(_files.length),
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
    if (_files.isEmpty) {
      return AppEmptyState(
        icon: AppIcons.trashDelete,
        title: _errorKey != null
            ? 'drive.load_error_title'.tr()
            : 'drive.trash_empty_title'.tr(),
        message: _errorKey != null
            ? _errorKey!.tr()
            : 'drive.trash_empty_message'.tr(),
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
                for (var i = 0; i < _files.length; i++) ...[
                  if (i > 0) const AppRowDivider(indent: 62),
                  _TrashRow(
                    file: _files[i],
                    onRestore: () => _restore(_files[i]),
                    onDelete: () => _deleteForever(_files[i]),
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

class _TrashRow extends StatelessWidget {
  const _TrashRow({
    required this.file,
    required this.onRestore,
    required this.onDelete,
  });

  final DriveFile file;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppRowMenu(
      title: file.name,
      subtitle: formatBytes(file.size),
      actions: [
        AppMenuAction(
          icon: AppIcons.refreshSync,
          label: 'drive.restore'.tr(),
          onTap: onRestore,
        ),
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'drive.delete_forever'.tr(),
          destructive: true,
          onTap: onDelete,
        ),
      ],
      child: AppListTile(
        leading: MediaThumb(path: null, mime: file.mimeType),
        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(formatBytes(file.size)),
        onTap: onRestore,
      ),
    );
  }
}
