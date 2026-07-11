import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/ui/app_ui.dart';
import 'clipboard_cubit.dart';
import 'widgets/clipboard_history_row.dart';
import 'widgets/clipboard_sync_toggle.dart';

/// Clipboard history (route `/clipboard`): the last 20 synced items — text and
/// images — with copy-again / save / delete / clear, plus the sync pause
/// toggle. Entry point: Settings → Sync → Clipboard history.
class ClipboardHistoryPage extends StatelessWidget {
  const ClipboardHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final selfFingerprint = getIt<DeviceIdentity>().fingerprint;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocBuilder<ClipboardCubit, ClipboardState>(
          builder: (context, state) {
            final rows = state.entries;
            return AppResponsivePane(
              maxWidth: 720,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: 'clipboard.title'.tr(),
                    subtitle: 'clipboard.items_count'.plural(rows.length),
                    onBack: () => Navigator.of(context).maybePop(),
                    actions: [
                      AppIconButton(
                        icon: AppIcons.moreMenu,
                        onPressed: rows.isEmpty
                            ? () {}
                            : () => _menu(context),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: ClipboardSyncToggle(),
                  ),
                  Expanded(
                    child: rows.isEmpty
                        ? AppEmptyState(
                            icon: AppIcons.clipboard,
                            title: 'clipboard.empty_title'.tr(),
                            message: 'clipboard.empty_message'.tr(),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(top: 8, bottom: 28),
                            children: [
                              AppGroup(
                                child: Column(
                                  children: [
                                    for (var i = 0; i < rows.length; i++) ...[
                                      if (i > 0)
                                        const AppRowDivider(indent: 62),
                                      ClipboardHistoryRow(
                                        entry: rows[i],
                                        selfFingerprint: selfFingerprint,
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

  Future<void> _menu(BuildContext context) async {
    final cubit = context.read<ClipboardCubit>();
    await showAppSheet<void>(
      context,
      icon: AppIcons.clipboard,
      title: 'clipboard.title'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.trashDelete,
            label: 'clipboard.clear_all'.tr(),
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
