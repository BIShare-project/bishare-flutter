import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/server/receive_folders.dart';
import '../../../core/ui/app_ui.dart';
import '../../file_manager/domain/managed_file.dart' show categoryLabel;
import '../domain/settings.dart' as s;
import 'settings_cubit.dart';

/// "Folders by type": received files sorted into a folder per type (Images,
/// Videos, Documents, Apps, …) or kept together, and, where the platform can
/// write outside the app, a folder of the person's own for any type.
Future<void> showTypeFoldersSheet(BuildContext context, SettingsCubit cubit) =>
    showAppSheet<void>(
      context,
      icon: AppIcons.folderOpen,
      title: 'settings.type_folders'.tr(),
      builder: (ctx) =>
          BlocProvider.value(value: cubit, child: const _TypeFolders()),
    );

class _TypeFolders extends StatelessWidget {
  const _TypeFolders();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return BlocBuilder<SettingsCubit, s.Settings>(
      builder: (context, state) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSwitchRow(
            icon: AppIcons.folder,
            title: 'settings.sort_by_type'.tr(),
            subtitle:
                (state.sortByType
                        ? 'settings.type_folders_on'
                        : 'settings.type_folders_off')
                    .tr(),
            value: state.sortByType,
            onChanged: cubit.setSortByType,
          ),
          if (state.sortByType) ...[
            for (final c in ReceiveFolders.categories) ...[
              const AppRowDivider(indent: 52),
              AppValueRow(
                icon: AppIcons.folder,
                title: categoryLabel(c),
                subtitle: _where(state, c),
                onTap: cubit.canPickTypeFolders
                    ? () => _choose(context, cubit, state, c)
                    : null,
              ),
            ],
            if (cubit.canPickTypeFolders)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'settings.type_folders_hint'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// Where files of [category] land: the chosen folder, or the type's
  /// subfolder of the save folder.
  static String _where(s.Settings state, String category) {
    final chosen = state.typeFolders[category];
    if (chosen != null && chosen.isNotEmpty) return _tidy(chosen);
    final base = state.resolvedSaveDir;
    return base.isEmpty ? category : _tidy('$base/$category');
  }

  /// The last two parts of a path ("…/BIShare/Images").
  static String _tidy(String path) {
    final parts = path
        .split(RegExp(r'[\\/]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 2) return path;
    return '…/${parts[parts.length - 2]}/${parts.last}';
  }

  Future<void> _choose(
    BuildContext context,
    SettingsCubit cubit,
    s.Settings state,
    String category,
  ) async {
    final hasOwn = (state.typeFolders[category] ?? '').isNotEmpty;
    final choice = await showAppSheet<String>(
      context,
      icon: AppIcons.folder,
      title: categoryLabel(category),
      subtitle: _where(state, category),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.folderOpen,
            label: 'settings.choose_folder'.tr(),
            onTap: () => Navigator.pop(ctx, 'choose'),
          ),
          if (hasOwn)
            AppSheetAction(
              icon: AppIcons.refreshSync,
              label: 'settings.use_default'.tr(),
              onTap: () => Navigator.pop(ctx, 'default'),
            ),
        ],
      ),
    );
    switch (choice) {
      case 'choose':
        final result = await cubit.pickTypeFolder(category);
        if (context.mounted) showFolderResult(context, result);
      case 'default':
        await cubit.resetTypeFolder(category);
    }
  }
}

/// Tell the person why a chosen folder was not taken.
void showFolderResult(BuildContext context, TypeFolderResult result) {
  final key = switch (result) {
    TypeFolderResult.noPermission => 'settings.folder_no_permission',
    TypeFolderResult.notWritable => 'settings.folder_not_writable',
    _ => null,
  };
  if (key == null) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(key.tr())));
}
