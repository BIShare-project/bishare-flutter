import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import 'history_cubit.dart';
import 'widgets/filter_bar.dart';
import 'widgets/history_row.dart';
import 'widgets/stats_row.dart';

/// History tab: the full transfer log (sent + received) with filter, search,
/// per-row open/share/delete, CSV export, and clear-all.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) {
            final cubit = context.read<HistoryCubit>();
            final rows = state.filtered;
            return AppResponsivePane(
              maxWidth: 760,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: 'history.title'.tr(),
                    subtitle: 'history.transfers_count'.plural(state.total),
                    actions: [
                      AppIconButton(
                        icon: AppIcons.moreMenu,
                        onPressed: state.total == 0
                            ? () {}
                            : () => _menu(context, cubit),
                      ),
                    ],
                  ),
                  StatsRow(
                    total: state.total,
                    sent: state.sentCount,
                    received: state.receivedCount,
                  ),
                  FilterBar(value: state.filter, onChanged: cubit.setFilter),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                    child: ShadInput(
                      placeholder: Text('history.search_placeholder'.tr()),
                      leading: const AppSvgIcon(AppIcons.search, size: 16),
                      onChanged: cubit.setQuery,
                    ),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? AppEmptyState(
                            icon: AppIcons.history,
                            title: state.total == 0
                                ? 'history.empty_none_title'.tr()
                                : 'history.empty_no_matches_title'.tr(),
                            message: state.total == 0
                                ? 'history.empty_none_message'.tr()
                                : 'history.empty_no_matches_message'.tr(),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(top: 4, bottom: 28),
                            children: [
                              AppGroup(
                                child: Column(
                                  children: [
                                    for (var i = 0; i < rows.length; i++) ...[
                                      if (i > 0)
                                        const AppRowDivider(indent: 62),
                                      HistoryRow(record: rows[i]),
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

  Future<void> _menu(BuildContext context, HistoryCubit cubit) async {
    await showAppSheet<void>(
      context,
      icon: AppIcons.history,
      title: 'history.title'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.downloadFile,
            label: 'history.export_csv'.tr(),
            onTap: () async {
              Navigator.pop(ctx);
              final path = await cubit.exportCsv();
              await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
            },
          ),
          AppSheetAction(
            icon: AppIcons.trashDelete,
            label: 'history.clear_history'.tr(),
            destructive: true,
            onTap: () {
              Navigator.pop(ctx);
              cubit.clearAll();
            },
          ),
        ],
      ),
    );
  }
}
