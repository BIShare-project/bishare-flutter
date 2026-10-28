import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/app_showcase.dart';
import '../../../core/ui/app_ui.dart';
import '../../history/presentation/history_page.dart';
import 'inbox_page.dart';

/// The Inbox tab (redesign-plan.md 2.2), in the same shape as Send and
/// Drive (owner 2026-10-28): a one-row header with the menu, then content
/// tabs, Received and History, that also swipe. The menu offers what the
/// open tab can do.
class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppScreenHeader(
              title: 'inbox.title'.tr(),
              actions: [
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
        ),
      ),
    );
  }
}
