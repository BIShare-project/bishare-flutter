import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_ui.dart';
import '../../send/presentation/send_selection_cubit.dart';
import '../../send/presentation/tray_cubit.dart';
import 'device_section.dart';
import 'send_selection_bar.dart';
import 'send_sheet.dart';

/// The Send tab on a computer (redesign-plan.md 3.11): a computer has no
/// photo library, so no tabs. A drop zone and the chosen files in the middle,
/// and the destinations always visible beside them: tap a device to send.
class SendDesktopPane extends StatelessWidget {
  const SendDesktopPane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 120),
            children: [
              AppScreenHeader(title: 'nav.tab_share'.tr()),
              const _DropZone(),
              const _Chosen(),
            ],
          ),
        ),
        Container(
          width: 340,
          decoration: BoxDecoration(
            color: t.surface,
            border: BorderDirectional(start: BorderSide(color: t.line)),
          ),
          child: ListView(
            padding: const EdgeInsets.only(top: 14, bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  'compose.send_to'.tr(),
                  style: AppType.pageTitle.copyWith(color: t.text),
                ),
              ),
              BlocSelector<SendSelectionCubit, SendSelection, bool>(
                selector: (s) => s.isEmpty,
                builder: (context, empty) => Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                  child: Text(
                    empty
                        ? 'compose.send_to_empty'.tr()
                        : 'compose.send_to_hint'.tr(),
                    style: AppType.secondary.copyWith(color: t.text2),
                  ),
                ),
              ),
              const DeviceSection(list: true),
              AppSectionHeader('compose.ways'.tr()),
              const SendWays(inSheet: false),
            ],
          ),
        ),
      ],
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tray = context.read<TrayCubit>();
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line, width: 1.5),
      ),
      child: Column(
        children: [
          AppSvgIcon(AppIcons.uploadFile, size: 28, color: t.text3),
          const SizedBox(height: 10),
          Text(
            'compose.drop_title'.tr(),
            textAlign: TextAlign.center,
            style: AppType.rowStrong.copyWith(fontSize: 16, color: t.text),
          ),
          const SizedBox(height: 4),
          Text(
            'compose.drop_body'.tr(),
            textAlign: TextAlign.center,
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'receive.choose_files'.tr(),
                icon: AppIcons.fileDocument,
                onPressed: tray.pickFiles,
              ),
              AppButton(
                label: 'compose.pick_folder'.tr(),
                icon: AppIcons.folder,
                variant: AppButtonVariant.secondary,
                onPressed: tray.pickFolder,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The chosen files, removable one by one.
class _Chosen extends StatelessWidget {
  const _Chosen();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BlocBuilder<SendSelectionCubit, SendSelection>(
      builder: (context, s) {
        if (s.isEmpty) return const SizedBox.shrink();
        final cubit = context.read<SendSelectionCubit>();
        final bytes = s.bytes;
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [
                        'compose.n_items'.plural(s.length),
                        if (bytes != null) formatBytes(bytes),
                      ].join(' · '),
                      style: AppType.secondary.copyWith(color: t.text2),
                    ),
                  ),
                  AppButton(
                    label: 'home.clear'.tr(),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    onPressed: cubit.clear,
                  ),
                ],
              ),
              AppGroup(
                card: true,
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < s.length; i++) ...[
                      if (i > 0) const AppRowDivider(indent: 72),
                      Builder(
                        builder: (context) {
                          final e = s.entries[i];
                          final name = e is FileEntry
                              ? e.file.name
                              : (e is AppEntry ? e.app.name : '');
                          return AppListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(9),
                              child: SizedBox.square(
                                dimension: 42,
                                child: SendEntryThumb(e, size: 42),
                              ),
                            ),
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: e.size == null
                                ? null
                                : Text(formatBytes(e.size!)),
                            trailing: AppIconButton(
                              icon: AppIcons.close,
                              color: t.text2,
                              tooltip: 'compose.remove'.tr(
                                namedArgs: {'name': name},
                              ),
                              onPressed: () => cubit.remove(e),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
