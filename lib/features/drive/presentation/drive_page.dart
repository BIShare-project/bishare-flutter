import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../../auth/presentation/auth_cubit.dart';
import '../../remote/data/cloud_transfer_service.dart';
import '../data/drive_service.dart';
import '../domain/drive_models.dart';
import 'drive_cubit.dart';
import 'widgets/drive_breadcrumb.dart';
import 'widgets/drive_dialogs.dart';
import 'widgets/drive_move_sheet.dart';
import 'widgets/drive_rows.dart';
import 'widgets/drive_share_sheet.dart';
import 'widgets/drive_upload.dart';
import 'widgets/storage_meter.dart';

/// Drive — the cloud file manager. Signed-out shows a sign-in prompt; signed-in
/// browses folders + files (breadcrumb navigation, sort, upload, per-item
/// actions) using the shared design kit so it reads as one language with the
/// rest of the app.
class DrivePage extends StatelessWidget {
  const DrivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, auth) {
        if (!auth.isAuthenticated) return const _SignedOut();
        return BlocProvider(
          create: (_) => DriveCubit(getIt<DriveService>())..open(null),
          child: const _DriveView(),
        );
      },
    );
  }
}

/// The signed-out gate: a header + empty state with a Sign in action.
class _SignedOut extends StatelessWidget {
  const _SignedOut();

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
                title: 'drive.title'.tr(),
                onBack: () => context.pop(),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppEmptyState(
                      icon: AppIcons.cloudSync,
                      title: 'drive.signed_out_title'.tr(),
                      message: 'drive.signed_out_message'.tr(),
                    ),
                    // Sign-in exists only once the launch flag turns on
                    // (this page itself is deep-link-only while hidden).
                    if (getIt<FeatureFlags>().loginEnabled) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: AppButton(
                          label: 'auth.sign_in'.tr(),
                          icon: AppIcons.logIn,
                          fullWidth: true,
                          onPressed: () => context.push('/login'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveView extends StatefulWidget {
  const _DriveView();

  @override
  State<_DriveView> createState() => _DriveViewState();
}

class _DriveViewState extends State<_DriveView> {
  final _scroll = ScrollController();

  DriveService get _service => getIt<DriveService>();
  CloudTransferService get _cloud => getIt<CloudTransferService>();
  DriveCubit get _cubit => context.read<DriveCubit>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _cubit.loadMore();
    }
  }

  void _handleBack(DriveState state) {
    if (state.isRoot) {
      context.pop();
    } else {
      _cubit.goUp();
    }
  }

  // ---- Header actions -------------------------------------------------------

  Future<void> _pickAndUpload(DriveState state) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    final paths = res?.paths.whereType<String>().toList() ?? const [];
    if (paths.isEmpty || !mounted) return;
    final count = await showDriveUpload(
      context,
      service: _service,
      files: [for (final p in paths) File(p)],
      folderId: state.folderId,
    );
    if (!mounted) return;
    if (count > 0) {
      await _cubit.onUploaded();
      if (mounted) {
        toast(
          context,
          'drive.uploaded_n'.plural(count),
          type: ToastType.success,
        );
      }
    }
  }

  Future<void> _sortMenu(DriveState state) async {
    await showAppSheet<void>(
      context,
      icon: AppIcons.sort,
      title: 'drive.sort_by'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in DriveSort.values)
            AppSheetAction(
              icon: s == state.sort ? AppIcons.check : AppIcons.circle,
              label: switch (s) {
                DriveSort.name => 'drive.sort_name'.tr(),
                DriveSort.newest => 'drive.sort_newest'.tr(),
                DriveSort.largest => 'drive.sort_largest'.tr(),
              },
              onTap: () {
                Navigator.pop(ctx);
                _cubit.setSort(s);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _moreMenu(DriveState state) async {
    await showAppSheet<void>(
      context,
      icon: AppIcons.moreMenu,
      title: 'drive.title'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.newFolder,
            label: 'drive.new_folder'.tr(),
            onTap: () {
              Navigator.pop(ctx);
              _createFolder();
            },
          ),
          AppSheetAction(
            icon: AppIcons.linkCopy,
            label: 'drive.manage_links'.tr(),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/drive/shares');
            },
          ),
          AppSheetAction(
            icon: AppIcons.trashDelete,
            label: 'drive.trash'.tr(),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/drive/trash');
            },
          ),
          AppSheetAction(
            icon: AppIcons.refreshSync,
            label: 'drive.refresh'.tr(),
            onTap: () {
              Navigator.pop(ctx);
              _cubit.refresh();
            },
          ),
        ],
      ),
    );
  }

  // ---- Mutations (with toast feedback) --------------------------------------

  Future<void> _createFolder() async {
    final name = await promptName(
      context,
      icon: AppIcons.newFolder,
      title: 'drive.new_folder'.tr(),
      subtitle: 'drive.new_folder_hint'.tr(),
      hint: 'drive.folder_name'.tr(),
      buttonLabel: 'drive.create'.tr(),
    );
    if (name == null || !mounted) return;
    _report(await _cubit.createFolder(name), 'drive.folder_created');
  }

  Future<void> _renameFolder(DriveFolder folder) async {
    final name = await promptName(
      context,
      icon: AppIcons.renameEdit,
      title: 'drive.rename'.tr(),
      hint: 'drive.folder_name'.tr(),
      buttonLabel: 'settings.save'.tr(),
      initial: folder.name,
    );
    if (name == null || !mounted) return;
    _report(await _cubit.renameFolder(folder.id, name), 'drive.renamed');
  }

  Future<void> _renameFile(DriveFile file) async {
    final name = await promptName(
      context,
      icon: AppIcons.renameEdit,
      title: 'drive.rename'.tr(),
      hint: 'drive.file_name'.tr(),
      buttonLabel: 'settings.save'.tr(),
      initial: file.name,
    );
    if (name == null || !mounted) return;
    _report(await _cubit.renameFile(file.id, name), 'drive.renamed');
  }

  Future<void> _moveFolder(DriveFolder folder) async {
    final dest = await showDriveMoveSheet(
      context,
      service: _service,
      excludeFolderId: folder.id,
    );
    if (dest == null || !mounted) return;
    _report(await _cubit.moveFolder(folder.id, dest.id), 'drive.moved');
  }

  Future<void> _moveFile(DriveFile file) async {
    final dest = await showDriveMoveSheet(context, service: _service);
    if (dest == null || !mounted) return;
    _report(await _cubit.moveFile(file.id, dest.id), 'drive.moved');
  }

  Future<void> _deleteFolder(DriveFolder folder) async {
    final ok = await confirmDestructive(
      context,
      title: 'drive.delete_folder_title'.tr(),
      subtitle: 'drive.delete_folder_message'.tr(namedArgs: {'name': folder.name}),
      confirmLabel: 'drive.delete_folder_confirm'.tr(),
    );
    if (!ok || !mounted) return;
    _report(await _cubit.deleteFolder(folder.id), 'drive.deleted');
  }

  Future<void> _deleteFile(DriveFile file) async {
    final ok = await confirmDestructive(
      context,
      title: 'drive.delete_file_title'.tr(),
      subtitle: 'drive.delete_file_message'.tr(namedArgs: {'name': file.name}),
      confirmLabel: 'drive.delete_file_confirm'.tr(),
    );
    if (!ok || !mounted) return;
    _report(await _cubit.deleteFile(file.id), 'drive.moved_to_trash');
  }

  void _share({String? fileId, String? folderId, required String name}) {
    showDriveShareSheet(
      context,
      service: _service,
      name: name,
      fileId: fileId,
      folderId: folderId,
    );
  }

  void _download(DriveFile file) {
    downloadDriveFile(context, service: _service, cloud: _cloud, file: file);
  }

  /// Toast the outcome of a mutation: [errorKey] (localized) on failure, or the
  /// [successKey] on success.
  void _report(String? errorKey, String successKey) {
    if (!mounted) return;
    if (errorKey != null) {
      toast(context, errorKey.tr(), type: ToastType.error);
    } else {
      toast(context, successKey.tr(), type: ToastType.success);
    }
  }

  // ---- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return BlocBuilder<DriveCubit, DriveState>(
      builder: (context, state) {
        return PopScope(
          canPop: state.isRoot,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _cubit.goUp();
          },
          child: Scaffold(
            backgroundColor: cs.background,
            body: SafeArea(
              child: AppResponsivePane(
                maxWidth: 760,
                child: Column(
                  children: [
                    AppScreenHeader(
                      title: state.currentName.isEmpty
                          ? 'drive.title'.tr()
                          : state.currentName,
                      onBack: () => _handleBack(state),
                      actions: [
                        AppIconButton(
                          icon: AppIcons.sort,
                          onPressed: () => _sortMenu(state),
                        ),
                        AppIconButton(
                          icon: AppIcons.uploadFile,
                          onPressed: () => _pickAndUpload(state),
                        ),
                        AppIconButton(
                          icon: AppIcons.moreMenu,
                          onPressed: () => _moreMenu(state),
                        ),
                      ],
                    ),
                    if (!state.isRoot)
                      DriveBreadcrumb(
                        trail: state.breadcrumb,
                        onTap: _cubit.open,
                      ),
                    Expanded(child: _body(state)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _body(DriveState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorKey != null && state.isEmpty) {
      return ListView(
        children: [
          AppEmptyState(
            icon: AppIcons.circleAlert,
            title: 'drive.load_error_title'.tr(),
            message: state.errorKey!.tr(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: AppButton(
              label: 'common.try_again'.tr(),
              icon: AppIcons.refreshSync,
              variant: AppButtonVariant.outline,
              fullWidth: true,
              onPressed: _cubit.refresh,
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _cubit.refresh,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(top: 6, bottom: 28),
        children: [
          if (state.isRoot && state.storage != null)
            StorageMeter(usage: state.storage!),
          if (state.isEmpty)
            AppEmptyState(
              icon: AppIcons.folderShared,
              title: 'drive.empty_title'.tr(),
              message: 'drive.empty_message'.tr(),
            )
          else
            AppGroup(
              child: Column(
                children: [
                  for (var i = 0; i < state.folders.length; i++) ...[
                    if (i > 0) const AppRowDivider(indent: 62),
                    DriveFolderRow(
                      folder: state.folders[i],
                      onOpen: () => _cubit.open(state.folders[i].id),
                      onRename: () => _renameFolder(state.folders[i]),
                      onMove: () => _moveFolder(state.folders[i]),
                      onShare: () => _share(
                        folderId: state.folders[i].id,
                        name: state.folders[i].name,
                      ),
                      onDelete: () => _deleteFolder(state.folders[i]),
                    ),
                  ],
                  for (var i = 0; i < state.files.length; i++) ...[
                    if (i > 0 || state.folders.isNotEmpty)
                      const AppRowDivider(indent: 62),
                    DriveFileRow(
                      file: state.files[i],
                      onTap: () => _download(state.files[i]),
                      onDownload: () => _download(state.files[i]),
                      onShare: () => _share(
                        fileId: state.files[i].id,
                        name: state.files[i].name,
                      ),
                      onRename: () => _renameFile(state.files[i]),
                      onMove: () => _moveFile(state.files[i]),
                      onDelete: () => _deleteFile(state.files[i]),
                    ),
                  ],
                ],
              ),
            ),
          if (state.loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
