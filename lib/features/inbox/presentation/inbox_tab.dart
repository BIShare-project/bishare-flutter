import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/ui/app_ui.dart';
import '../../history/presentation/history_page.dart';
import 'inbox_page.dart';

/// The Kotak Masuk tab (redesign-plan.md 2.2): what arrived, and the history
/// of every transfer, as two segments under one title. Drive left this tab
/// for a tab of its own.
class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final segment = AppSegmented<bool>(
      value: _history,
      options: [(false, 'history.received'.tr()), (true, 'history.title'.tr())],
      onChanged: (v) => setState(() => _history = v),
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
    );
    return _history
        ? HistoryPage(segment: segment)
        : InboxPage(segment: segment);
  }
}
