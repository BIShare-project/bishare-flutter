import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../../core/ui/shell_tab.dart';
import '../../inbox/domain/inbox_groups.dart';
import 'history_cubit.dart';

/// The History segment of the Inbox (redesign-plan.md 5.5): every transfer,
/// sent and received, searchable, filtered by direction, grouped by day with
/// the total of what is shown. A row opens its detail; the menu exports CSV
/// or clears the history.
/// Whether History shows its search field. The magnifier sits in the Inbox
/// tab's header, so the header and the page share it.
final historySearchOpen = ValueNotifier<bool>(false);

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) {
            final cubit = context.read<HistoryCubit>();
            final rows = state.filtered;
            final total = rows.fold<int>(0, (s, r) => s + r.fileSize);
            return AppResponsivePane(
              maxWidth: 760,
              child: Column(
                children: [
                  if (state.total > 0) ...[
                    ValueListenableBuilder<bool>(
                      valueListenable: historySearchOpen,
                      builder: (context, open, _) => open
                          ? _SearchRow(cubit: cubit)
                          : const SizedBox.shrink(),
                    ),
                    _Toolbar(
                      text: [
                        'history.transfers_count'.plural(rows.length),
                        'history.total_size'.tr(
                          namedArgs: {'size': formatBytes(total)},
                        ),
                      ].join(' · '),
                      filter: state.filter,
                      cubit: cubit,
                    ),
                  ],
                  Expanded(
                    child: state.total == 0
                        ? AppEmptyState(
                            icon: AppIcons.history,
                            title: 'history.empty_none_title'.tr(),
                            message: 'history.empty_none_message'.tr(),
                            action: AppButton(
                              label: 'history.send_a_file'.tr(),
                              onPressed: () =>
                                  shellTabRequest.value = ShellTabId.send,
                            ),
                          )
                        : rows.isEmpty
                        ? AppEmptyState(
                            icon: AppIcons.search,
                            title: 'history.empty_no_matches_title'.tr(),
                            message: 'history.empty_no_matches_message'.tr(),
                          )
                        : _List(rows: rows),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The search field, open from the header's magnifier. Closing it clears
/// the search.
class _SearchRow extends StatefulWidget {
  const _SearchRow({required this.cubit});

  final HistoryCubit cubit;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  late final TextEditingController _text = TextEditingController(
    text: widget.cubit.state.query,
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 6, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: AppSearchField(
              hint: 'history.search_placeholder'.tr(),
              controller: _text,
              focusNode: _focus,
              onChanged: widget.cubit.setQuery,
              margin: const EdgeInsetsDirectional.fromSTEB(16, 0, 2, 0),
            ),
          ),
          AppButton(
            label: 'common.cancel'.tr(),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            onPressed: () {
              widget.cubit.setQuery('');
              historySearchOpen.value = false;
            },
          ),
        ],
      ),
    );
  }
}

/// What is shown (count and size) and the direction filter, one row.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.text,
    required this.filter,
    required this.cubit,
  });

  final String text;
  final HistoryFilter filter;
  final HistoryCubit cubit;

  Future<void> _filterMenu(BuildContext context) async {
    final pick = await showAppSheet<HistoryFilter>(
      context,
      icon: AppIcons.filter,
      title: 'history.filter_title'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in HistoryFilter.values)
            AppSheetAction(
              icon: f == filter ? AppIcons.check : AppIcons.circle,
              label: f.label,
              onTap: () => Navigator.pop(ctx, f),
            ),
        ],
      ),
    );
    if (pick != null) cubit.setFilter(pick);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = filter != HistoryFilter.all;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.secondary.copyWith(
                color: t.text2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _filterMenu(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSvgIcon(
                        AppIcons.filter,
                        size: 18,
                        color: on ? t.accent : t.text,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        filter.label,
                        style: AppType.secondary.copyWith(
                          color: on ? t.accent : t.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the history list: a day heading or a transfer.
sealed class _Line {}

final class _Day extends _Line {
  _Day(this.label);
  final String label;
}

final class _Item extends _Line {
  _Item(this.record, {required this.first});
  final TransferRecord record;
  final bool first;
}

class _List extends StatelessWidget {
  const _List({required this.rows});

  final List<TransferRecord> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locale = context.locale.toLanguageTag();
    final lines = <_Line>[];
    String? day;
    for (final r in rows) {
      final d = dayLabel(r.timestamp, locale);
      final first = d != day;
      if (first) lines.add(_Day(d));
      day = d;
      lines.add(_Item(r, first: first));
    }
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 120),
          sliver: SliverList.builder(
            itemCount: lines.length,
            itemBuilder: (context, i) => switch (lines[i]) {
              _Day(:final label) => Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 4),
                child: Text(
                  label,
                  style: AppType.label.copyWith(color: t.text2),
                ),
              ),
              _Item(:final record, :final first) => _Row(
                record: record,
                first: first,
                locale: locale,
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.record, required this.first, required this.locale});

  final TransferRecord record;
  final bool first;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = record;
    final sent = r.direction == 'sent';
    final who = (sent ? 'history.to_alias' : 'history.from_alias').tr(
      namedArgs: {'alias': r.deviceAlias},
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first) const AppRowDivider(indent: 72),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => _open(context, r),
            onLongPress: () => _detail(context, r),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
                child: Row(
                  children: [
                    _DirectionGlyph(record: r, sent: sent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shownName(r),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.row.copyWith(color: t.text),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              who,
                              formatBytes(r.fileSize),
                              timeLabel(r.timestamp, locale),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.secondary.copyWith(color: t.text2),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: AppIcons.moreMenu,
                      tooltip: 'inbox.more'.tr(),
                      onPressed: () => _detail(context, r),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Like a Drive row: a tap opens the file while it is still on this
  /// device, otherwise its details; the ⋯ always shows the details.
  void _open(BuildContext context, TransferRecord r) {
    final path = r.savedPath;
    if (path == null || !File(path).existsSync()) {
      _detail(context, r);
      return;
    }
    showFilePreview(
      context,
      path: path,
      name: r.fileName,
      mimeType:
          r.fileType ??
          lookupMimeType(r.fileName) ??
          'application/octet-stream',
      size: r.fileSize,
    );
  }

  Future<void> _detail(BuildContext context, TransferRecord r) {
    final cubit = context.read<HistoryCubit>();
    final sent = r.direction == 'sent';
    final when = DateFormat.yMMMd(locale).add_Hm().format(r.timestamp);
    final has = r.savedPath != null && File(r.savedPath!).existsSync();
    return showAppSheet<void>(
      context,
      title: shownName(r),
      subtitle: (sent ? 'history.sent' : 'history.received').tr(),
      builder: (ctx) {
        final t = ctx.tokens;
        Widget kv(String k, String v, {int lines = 1}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k, style: AppType.body.copyWith(color: t.text2)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  v,
                  textAlign: TextAlign.end,
                  maxLines: lines,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body.copyWith(
                    color: t.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            kv('history.csv_device'.tr(), r.deviceAlias),
            if (shownName(r) != r.fileName)
              kv('inbox.detail_saved_as'.tr(), r.fileName, lines: 2),
            kv('history.csv_size'.tr(), formatBytes(r.fileSize)),
            kv('history.csv_date'.tr(), when),
            kv(
              'history.csv_verified'.tr(),
              (r.verified ? 'history.yes' : 'history.no').tr(),
            ),
            const SizedBox(height: 14),
            if (has) ...[
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'history.share'.tr(),
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.large,
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(files: [XFile(r.savedPath!)]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'history.open'.tr(),
                      size: AppButtonSize.large,
                      onPressed: () {
                        Navigator.pop(ctx);
                        showFilePreview(
                          context,
                          path: r.savedPath!,
                          name: r.fileName,
                          mimeType:
                              r.fileType ??
                              lookupMimeType(r.fileName) ??
                              'application/octet-stream',
                          size: r.fileSize,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            // Red like the Inbox detail sheet's delete row.
            AppValueRow(
              icon: AppIcons.trashDelete,
              title: 'history.remove'.tr(),
              destructive: true,
              chevron: false,
              onTap: () async {
                Navigator.pop(ctx);
                final yes = await showAppConfirm(
                  context,
                  title: 'history.remove_title'.tr(),
                  message:
                      (has ? 'history.remove_body_file' : 'history.remove_body')
                          .tr(),
                  confirmLabel: 'history.remove'.tr(),
                );
                if (yes) await cubit.deleteEntry(r);
              },
            ),
          ],
        );
      },
    );
  }
}

/// The file's kind, with a small arrow on the corner: up for sent, down for
/// received.
class _DirectionGlyph extends StatelessWidget {
  const _DirectionGlyph({required this.record, required this.sent});

  final TransferRecord record;
  final bool sent;

  /// A received photo still on this device, at row size.
  Widget? _picture(BuildContext context) {
    final path = record.savedPath;
    if (path == null || !isImage(record)) return null;
    final px = (44 * MediaQuery.devicePixelRatioOf(context)).round();
    return Image(
      image: ResizeImage(
        FileImage(File(path)),
        width: px,
        policy: ResizeImagePolicy.fit,
      ),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _glyph(context),
    );
  }

  Widget _glyph(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.sunken,
      child: Center(
        child: AppSvgIcon(
          fileIcon(record.fileType ?? ''),
          size: 22,
          color: t.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox.square(
      dimension: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: SizedBox.square(
              dimension: 44,
              child: _picture(context) ?? _glyph(context),
            ),
          ),
          PositionedDirectional(
            end: -3,
            bottom: -3,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.bg,
                shape: BoxShape.circle,
                border: Border.all(color: t.line),
              ),
              child: Semantics(
                label: (sent ? 'history.sent' : 'history.received').tr(),
                child: AppSvgIcon(
                  sent ? AppIcons.arrowUp : AppIcons.arrowDown,
                  size: 12,
                  color: t.text,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The History menu (the ⋯ of the Inbox tab on History): export as CSV,
/// clear the history.
Future<void> showHistoryMenu(BuildContext context) {
  final cubit = context.read<HistoryCubit>();
  return showAppSheet<void>(
    context,
    title: 'history.title'.tr(),
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppValueRow(
          icon: AppIcons.downloadFile,
          title: 'history.export_csv'.tr(),
          chevron: false,
          onTap: () async {
            Navigator.pop(ctx);
            final path = await cubit.exportCsv();
            await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
          },
        ),
        AppValueRow(
          icon: AppIcons.trashDelete,
          title: 'history.clear_history'.tr(),
          destructive: true,
          chevron: false,
          onTap: () async {
            Navigator.pop(ctx);
            final yes = await showAppConfirm(
              context,
              title: 'history.clear_title'.tr(),
              message: 'history.clear_body'.tr(),
              confirmLabel: 'inbox.clear'.tr(),
            );
            if (yes) await cubit.clearAll();
          },
        ),
      ],
    ),
  );
}
