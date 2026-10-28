import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../settings/domain/settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import 'clipboard_cubit.dart';

/// Clipboard history (route `/clipboard`): the last 20 synced items, text
/// and images, with copy-again / save / delete / clear, and the sync switch
/// on top. Entry point: Settings → Devices and sync → Clipboard history.
class ClipboardHistoryPage extends StatelessWidget {
  const ClipboardHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selfFingerprint = getIt<DeviceIdentity>().fingerprint;
    return Scaffold(
      backgroundColor: t.bg,
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
                      if (rows.isNotEmpty)
                        AppIconButton(
                          icon: AppIcons.moreMenu,
                          tooltip: 'inbox.more'.tr(),
                          onPressed: () => _menu(context),
                        ),
                    ],
                  ),
                  const _SyncSwitch(),
                  const AppRowDivider(indent: 0),
                  Expanded(
                    child: rows.isEmpty
                        ? AppEmptyState(
                            icon: AppIcons.clipboard,
                            title: 'clipboard.empty_title'.tr(),
                            message: 'clipboard.empty_message'.tr(),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(top: 4, bottom: 28),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const AppRowDivider(indent: 70),
                            itemBuilder: (context, i) => _ClipRow(
                              entry: rows[i],
                              selfFingerprint: selfFingerprint,
                            ),
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
    await showActionSheet(
      context,
      title: 'clipboard.title'.tr(),
      actions: [
        AppMenuAction(
          icon: AppIcons.trashDelete,
          label: 'clipboard.clear_all'.tr(),
          destructive: true,
          onTap: cubit.clearAll,
        ),
      ],
    );
  }
}

/// Whether clipboard sync is on, and a quick pause: the same setting as
/// Settings → Universal clipboard.
class _SyncSwitch extends StatelessWidget {
  const _SyncSwitch();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsCubit, Settings>(
      buildWhen: (a, b) => a.clipboardSync != b.clipboardSync,
      builder: (context, settings) {
        final on = settings.clipboardSync;
        return AppSwitchRow(
          icon: AppIcons.clipboard,
          title: 'settings.universal_clipboard'.tr(),
          subtitle: on
              ? 'clipboard.sync_active'.tr()
              : 'clipboard.sync_paused'.tr(),
          value: on,
          onChanged: context.read<SettingsCubit>().setClipboardSync,
        );
      },
    );
  }
}

/// One synced item: an image thumbnail or a text snippet. Tap copies it
/// again; ⋯, a long press or a right click opens copy / save / delete;
/// swipe deletes, like History rows.
class _ClipRow extends StatelessWidget {
  const _ClipRow({required this.entry, required this.selfFingerprint});

  final ClipboardHistoryData entry;

  /// Our own fingerprint: entries we broadcast show "You" as the source.
  final String selfFingerprint;

  bool get _isImage => entry.kind == 'image';

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = _isImage
        ? (entry.fileName ?? 'clipboard.image_label'.tr())
        : (entry.textContent ?? '').replaceAll('\n', ' ');
    final from = entry.senderFingerprint == selfFingerprint
        ? 'clipboard.you'.tr()
        : entry.senderAlias;
    final thumb = MediaThumb(
      path: _isImage ? (entry.filePath ?? entry.previewPath) : null,
      mime: _isImage ? entry.mime : 'text/plain',
    );
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: t.danger,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 22),
        child: AppSvgIcon(AppIcons.trashDelete, color: t.onDanger),
      ),
      onDismissed: (_) => context.read<ClipboardCubit>().remove(entry),
      child: AppRowMenu(
        title: title,
        subtitle: from,
        actions: _actions(context),
        child: AppListTile(
          leading: thumb,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'clipboard.row_subtitle'.tr(
              namedArgs: {'from': from, 'time': _time(entry.createdAt)},
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _copy(context),
          trailing: AppIconButton(
            icon: AppIcons.moreMenu,
            tooltip: 'inbox.more'.tr(),
            onPressed: () => showActionSheet(
              context,
              title: title,
              subtitle: from,
              leading: MediaThumb(
                path: _isImage ? (entry.filePath ?? entry.previewPath) : null,
                mime: _isImage ? entry.mime : 'text/plain',
                size: 48,
                radius: 12,
              ),
              actions: _actions(context),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final ok = await context.read<ClipboardCubit>().copyAgain(entry);
    if (!context.mounted) return;
    if (ok) {
      toast(context, 'clipboard.copied'.tr());
    } else {
      toast(context, 'clipboard.copy_failed'.tr(), type: ToastType.error);
    }
  }

  Future<void> _save(BuildContext context) async {
    final path = await context.read<ClipboardCubit>().saveToFiles(entry);
    if (!context.mounted) return;
    if (path != null) {
      toast(context, 'clipboard.saved'.tr());
    } else {
      toast(context, 'clipboard.save_failed'.tr(), type: ToastType.error);
    }
  }

  List<AppMenuAction> _actions(BuildContext context) {
    final hasFile =
        entry.filePath != null && File(entry.filePath!).existsSync();
    return [
      AppMenuAction(
        icon: AppIcons.copyDuplicate,
        label: 'common.copy'.tr(),
        onTap: () => _copy(context),
      ),
      if (_isImage && hasFile)
        AppMenuAction(
          icon: AppIcons.downloadFile,
          label: 'clipboard.save'.tr(),
          onTap: () => _save(context),
        ),
      AppMenuAction(
        icon: AppIcons.trashDelete,
        label: 'common.delete'.tr(),
        destructive: true,
        onTap: () => context.read<ClipboardCubit>().remove(entry),
      ),
    ];
  }

  static String _time(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    String p(int v) => v.toString().padLeft(2, '0');
    return sameDay
        ? '${p(t.hour)}:${p(t.minute)}'
        : '${t.year}-${p(t.month)}-${p(t.day)}';
  }
}
