import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_showcase.dart';
import '../../../core/ui/app_ui.dart';
import '../../history/presentation/history_page.dart';
import 'inbox_cubit.dart';
import 'inbox_page.dart';
import 'widgets/inbox_preview_pane.dart';

/// The Inbox tab (redesign-plan.md 2.2), in the same shape as Send and
/// Drive (owner 2026-10-28): a one-row header with the menu, then content
/// tabs, Received and History, that also swipe. The menu offers what the
/// open tab can do.
class InboxTab extends StatefulWidget {
  const InboxTab({super.key, this.openNewest = false});

  /// On an open iPhone Duo, start with the newest file in the preview (the
  /// store screenshots); otherwise the preview opens when a file is tapped.
  final bool openNewest;

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _preview.addListener(_onPreview);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  /// The file shown beside the list on an open iPhone Duo.
  final ValueNotifier<int?> _preview = ValueNotifier(null);

  /// Closed by hand: [InboxTab.openNewest] does not reopen it.
  bool _closed = false;

  void _onPreview() {
    if (_preview.value == null) _closed = true;
  }

  @override
  void dispose() {
    _preview.removeListener(_onPreview);
    _tabs.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final list = Column(
      children: [
        AppScreenHeader(
          title: 'inbox.title'.tr(),
          actions: [
            if (_tabs.index == 1)
              AppIconButton(
                icon: AppIcons.search,
                tooltip: 'history.search_placeholder'.tr(),
                onPressed: () =>
                    historySearchOpen.value = !historySearchOpen.value,
              ),
            AppShowcase(
              showcaseKey: ShowcaseKeys.inboxFiles,
              title: 'showcase.inbox_files_title'.tr(),
              description: 'showcase.inbox_files_body'.tr(),
              targetRadius: 22,
              child: AppIconButton(
                icon: AppIcons.moreMenu,
                tooltip: 'inbox.more'.tr(),
                onPressed: () => _tabs.index == 0
                    ? showInboxMenu(context)
                    : showHistoryMenu(context),
              ),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: AppTabBar(
            controller: _tabs,
            tabs: [
              AppTab('history.received'.tr()),
              AppTab('history.title'.tr()),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [InboxPage(), HistoryPage()],
          ),
        ),
      ],
    );
    // An open iPhone Duo: the received files beside the one chosen, split at
    // the fold when it is half open. Phones, iPads and computers: the list.
    // An open iPhone Duo: tapping a file opens it beside the list (split at
    // the fold when half open); its close button gives the list the whole
    // width again. Phones, iPads and computers: the list, as before.
    final body = context.isFoldableOpen
        ? InboxPreviewScope(
            selected: _preview,
            child: ValueListenableBuilder<int?>(
              valueListenable: _preview,
              builder: (context, chosen, _) {
                if (chosen == null && widget.openNewest && !_closed) {
                  final newest = context.select<InboxCubit, int?>(
                    (c) => c.state.isEmpty
                        ? null
                        : (c.state.toList()..sort(
                                (a, b) => b.timestamp.compareTo(a.timestamp),
                              ))
                              .first
                              .id,
                  );
                  if (newest != null) {
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _preview.value ??= newest,
                    );
                  }
                }
                final open =
                    chosen != null &&
                    context.select<InboxCubit, bool>(
                      (c) => c.state.any((r) => r.id == chosen),
                    );
                if (!open) return list;
                return FoldSplit(
                  left: list,
                  right: const InboxPreviewPane(),
                  flat: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: list),
                      const SizedBox(width: 360, child: InboxPreviewPane()),
                    ],
                  ),
                );
              },
            ),
          )
        : list;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(bottom: false, child: body),
    );
  }
}
