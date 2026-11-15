import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/app_ui.dart';

/// The root of Android's shared internal storage.
const androidStorageRoot = '/storage/emulated/0';

/// Android: choose a folder anywhere on internal storage, the root included.
/// The system folder picker refuses the storage root (and Download), while
/// with All files access the app may write anywhere there, so the folder is
/// chosen here instead. Returns the chosen path, or null when closed.
Future<String?> showFolderBrowser(BuildContext context, {String? start}) =>
    showAppSheet<String>(
      context,
      icon: AppIcons.folderOpen,
      title: 'folders.title'.tr(),
      builder: (ctx) => _FolderBrowser(start: _startDir(start)),
    );

/// The in-app browser on Android, starting at [start]; null elsewhere, where
/// the system picker is used.
Future<String?> Function()? folderChooser(
  BuildContext context, {
  String? start,
}) => Platform.isAndroid
    ? () => showFolderBrowser(context, start: start)
    : null;

/// A path for a settings row: "Internal storage" for Android's storage root,
/// which reads as "…/emulated/0" otherwise; null for any other path.
String? storageRootLabel(String path) =>
    path == androidStorageRoot ? 'folders.storage_root'.tr() : null;

String _startDir(String? start) {
  if (start == null || !start.startsWith(androidStorageRoot)) {
    return androidStorageRoot;
  }
  return Directory(start).existsSync() ? start : androidStorageRoot;
}

class _FolderBrowser extends StatefulWidget {
  const _FolderBrowser({required this.start});

  final String start;

  @override
  State<_FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<_FolderBrowser> {
  late String _dir = widget.start;

  bool get _atRoot => _dir == androidStorageRoot;

  /// Folders inside [_dir], by name. Hidden folders are left out, and so is
  /// Android/ at the root: other apps' private data, which cannot be written.
  List<String> _children() {
    try {
      final names = <String>[
        for (final e in Directory(_dir).listSync(followLinks: false))
          if (e is Directory) e.path.split('/').last,
      ];
      names.removeWhere(
        (n) => n.startsWith('.') || (_atRoot && n == 'Android'),
      );
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return names;
    } on FileSystemException {
      return const [];
    }
  }

  /// "Internal storage / New / Photos".
  String get _label {
    final rest = _dir.substring(androidStorageRoot.length);
    final parts = rest.split('/').where((p) => p.isNotEmpty);
    return ['folders.storage_root'.tr(), ...parts].join(' / ');
  }

  void _up() =>
      setState(() => _dir = _dir.substring(0, _dir.lastIndexOf('/')));

  Future<void> _newFolder() async {
    final controller = TextEditingController();
    final name = await showAppSheet<String>(
      context,
      icon: AppIcons.newFolder,
      title: 'folders.new_folder'.tr(),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text.trim());
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: controller,
              autofocus: true,
              hint: 'folders.new_folder_hint'.tr(),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'folders.create'.tr(),
              fullWidth: true,
              onPressed: submit,
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name == null || name.isEmpty || name.contains('/') || name == '..') {
      return;
    }
    final dir = Directory('$_dir/$name');
    try {
      if (!dir.existsSync()) dir.createSync();
      if (mounted) setState(() => _dir = dir.path);
    } on FileSystemException {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('folders.create_failed'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final children = _children();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_label, style: AppType.secondary.copyWith(color: t.text2)),
        const SizedBox(height: 8),
        // The list scrolls by itself, so both buttons stay in view however
        // many folders there are.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.45,
          ),
          child: SingleChildScrollView(
            key: ValueKey(_dir),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_atRoot)
                  AppSheetAction(
                    icon: AppIcons.chevronLeft,
                    label: 'folders.up'.tr(),
                    onTap: _up,
                  ),
                for (final name in children)
                  AppSheetAction(
                    icon: AppIcons.folder,
                    label: name,
                    onTap: () => setState(() => _dir = '$_dir/$name'),
                  ),
                if (children.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'folders.empty'.tr(),
                      textAlign: TextAlign.center,
                      style: AppType.secondary.copyWith(color: t.text2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'folders.new_folder'.tr(),
          icon: AppIcons.newFolder,
          variant: AppButtonVariant.secondary,
          fullWidth: true,
          onPressed: _newFolder,
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'folders.use_this'.tr(),
          fullWidth: true,
          onPressed: () => Navigator.pop(context, _dir),
        ),
      ],
    );
  }
}
