import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_ui.dart';
import '../../send/data/send_media_library.dart';
import '../../send/presentation/send_selection_cubit.dart';
import 'send_sheet.dart';

/// A small picture of one selected item: its thumbnail, or its file glyph.
class SendEntryThumb extends StatelessWidget {
  const SendEntryThumb(this.entry, {super.key, this.size = 30});

  final SendEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final e = entry;
    Widget glyph(String icon) => ColoredBox(
      color: context.tokens.sunken,
      child: Center(
        child: AppSvgIcon(icon, size: size * 0.5, color: context.tokens.text2),
      ),
    );
    return switch (e) {
      AssetEntry(:final asset) => Image(
        image: AssetThumbProvider(asset, px: px.clamp(60, 200)),
        fit: BoxFit.cover,
      ),
      AppEntry(:final app) =>
        app.icon == null
            ? glyph(AppIcons.gridView)
            : Image.memory(app.icon!, fit: BoxFit.cover, cacheWidth: px),
      FileEntry(:final file) =>
        file.mimeType.startsWith('image/')
            ? Image.file(
                File(file.path),
                fit: BoxFit.cover,
                cacheWidth: px,
                errorBuilder: (_, _, _) => glyph(AppIcons.image),
              )
            : glyph(fileIcon(file.mimeType)),
    };
  }
}

/// The floating bar of the Send tab: clear, what is selected, and Send. Only
/// this bar rebuilds when the selection changes.
class SendSelectionBar extends StatelessWidget {
  const SendSelectionBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendSelectionCubit, SendSelection>(
      builder: (context, s) {
        final bytes = s.bytes;
        return AppSelectionBar(
          visible: s.isNotEmpty,
          onClear: context.read<SendSelectionCubit>().clear,
          onSummaryTap: () => showSelectionReview(context),
          summary: AppSelectionSummary(
            title: 'compose.n_items'.plural(s.length),
            subtitle: bytes == null ? null : formatBytes(bytes),
            thumbs: [for (final e in s.entries.take(3)) SendEntryThumb(e)],
          ),
          primary: ('home.send'.tr(), () => showSendSheet(context)),
        );
      },
    );
  }
}

/// What is selected, with a way to remove items, clear, or send.
Future<void> showSelectionReview(BuildContext context) => showAppSheet<void>(
  context,
  title: 'compose.selected'.tr(),
  builder: (ctx) => BlocBuilder<SendSelectionCubit, SendSelection>(
    bloc: context.read<SendSelectionCubit>(),
    builder: (ctx, s) {
      final t = ctx.tokens;
      final cubit = context.read<SendSelectionCubit>();
      if (s.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        });
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: s.length,
              itemBuilder: (ctx, i) {
                final e = s.entries[i];
                final name = switch (e) {
                  AssetEntry(:final asset) => asset.title ?? 'home.photos'.tr(),
                  AppEntry(:final app) => app.name,
                  FileEntry(:final file) => file.name,
                };
                return AppListTile(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox.square(
                      dimension: 44,
                      child: SendEntryThumb(e, size: 44),
                    ),
                  ),
                  title: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: e.size == null ? null : Text(formatBytes(e.size!)),
                  trailing: AppIconButton(
                    icon: AppIcons.close,
                    color: t.text2,
                    tooltip: 'compose.remove'.tr(namedArgs: {'name': name}),
                    onPressed: () => cubit.remove(e),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'home.clear'.tr(),
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    cubit.clear();
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  label: 'home.send'.tr(),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    showSendSheet(context);
                  },
                ),
              ),
            ],
          ),
        ],
      );
    },
  ),
);
