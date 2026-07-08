import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import 'inbox_cubit.dart';
import 'web_access_sheet.dart';
import 'widgets/inbox_row.dart';
import 'widgets/selection_bar.dart';

/// Inbox tab: received files with a pinch-zoom image gallery, batch select
/// (save/delete), save-to-Photos, share, and swipe-delete.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  bool _selecting = false;
  final Set<int> _selected = {};

  bool _isMedia(String? m) =>
      (m?.startsWith('image/') ?? false) || (m?.startsWith('video/') ?? false);

  void _enterSelection(int id) => setState(() {
    _selecting = true;
    _selected
      ..clear()
      ..add(id);
  });

  void _exitSelection() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _toggle(int id) => setState(() {
    _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocBuilder<InboxCubit, List<TransferRecord>>(
          builder: (context, items) {
            final cubit = context.read<InboxCubit>();
            final hasMedia = items.any((r) => _isMedia(r.fileType));
            final selectedRecords = items
                .where((r) => _selected.contains(r.id))
                .toList();
            return AppResponsivePane(
              maxWidth: 760,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: _selecting
                        ? 'inbox.n_selected'.tr(
                            namedArgs: {'count': '${_selected.length}'},
                          )
                        : 'inbox.title'.tr(),
                    subtitle: _selecting
                        ? null
                        : items.isEmpty
                        ? 'inbox.received_appear'.tr()
                        : 'inbox.n_files_received'.plural(items.length),
                    actions: [
                      if (_selecting)
                        ShadButton.ghost(
                          onPressed: _exitSelection,
                          child: Text('inbox.done'.tr()),
                        )
                      else ...[
                        AppIconButton(
                          icon: AppIcons.folder,
                          onPressed: () => context.push('/files'),
                        ),
                        AppIconButton(
                          icon: AppIcons.qrShare,
                          onPressed: () => showWebAccess(context),
                        ),
                        if (items.isNotEmpty) ...[
                          if (hasMedia)
                            AppIconButton(
                              icon: AppIcons.squareCheck,
                              onPressed: () => _enterSelection(items.first.id),
                            ),
                          AppIconButton(
                            icon: AppIcons.moreMenu,
                            onPressed: () => _menu(context, cubit, items),
                          ),
                        ],
                      ],
                    ],
                  ),
                  if (_selecting)
                    SelectionBar(
                      total: items.length,
                      selected: _selected.length,
                      canSave:
                          InboxCubit.canSaveToPhotos &&
                          selectedRecords.any((r) => _isMedia(r.fileType)),
                      onSelectAll: () => setState(() {
                        if (_selected.length == items.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(items.map((r) => r.id));
                        }
                      }),
                      onSave: () async {
                        final n = await cubit.saveAllMedia(selectedRecords);
                        if (context.mounted) {
                          toast(
                            context,
                            'inbox.saved_n_to_photos'.tr(
                              namedArgs: {'count': '$n'},
                            ),
                            type: ToastType.success,
                          );
                        }
                        _exitSelection();
                      },
                      onDelete: () async {
                        await cubit.deleteMany(selectedRecords);
                        _exitSelection();
                      },
                    ),
                  Expanded(
                    child: items.isEmpty
                        ? AppEmptyState(
                            icon: AppIcons.notification,
                            title: 'inbox.empty_title'.tr(),
                            message: 'inbox.empty_message'.tr(),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(top: 4, bottom: 28),
                            children: [
                              AppGroup(
                                child: Column(
                                  children: [
                                    for (var i = 0; i < items.length; i++) ...[
                                      if (i > 0)
                                        const AppRowDivider(indent: 62),
                                      InboxRow(
                                        record: items[i],
                                        selecting: _selecting,
                                        selected: _selected.contains(
                                          items[i].id,
                                        ),
                                        onToggle: () => _toggle(items[i].id),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    InboxCubit cubit,
    List<TransferRecord> items,
  ) async {
    await showAppSheet<void>(
      context,
      icon: AppIcons.notification,
      title: 'inbox.title'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (InboxCubit.canSaveToPhotos &&
              items.any((r) => _isMedia(r.fileType)))
            AppSheetAction(
              icon: AppIcons.imageDown,
              label: 'inbox.save_all_media'.tr(),
              onTap: () async {
                Navigator.pop(ctx);
                final n = await cubit.saveAllMedia(items);
                if (context.mounted) {
                  toast(
                    context,
                    'inbox.saved_n_to_photos'.tr(namedArgs: {'count': '$n'}),
                    type: ToastType.success,
                  );
                }
              },
            ),
          AppSheetAction(
            icon: AppIcons.trashDelete,
            label: 'inbox.clear_inbox'.tr(),
            destructive: true,
            onTap: () {
              Navigator.pop(ctx);
              cubit.deleteMany(List.of(items));
            },
          ),
        ],
      ),
    );
  }
}
