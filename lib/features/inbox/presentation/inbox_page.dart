import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../../core/ui/shell_tab.dart';
import '../../settings/domain/settings.dart' as s;
import '../../settings/presentation/settings_cubit.dart';
import '../domain/inbox_groups.dart';
import 'inbox_cubit.dart';
import 'web_access_sheet.dart';
import 'widgets/received_actions.dart';

/// The Received segment of the Inbox (redesign-plan.md 5.1 to 5.4): files
/// grouped by sender and sitting, photos as a 4-column grid and other files
/// as rows, a dot on groups that arrived since the last visit. Long press or
/// Select starts choosing; the action bar saves, shares or deletes.
class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

/// One line of the lazily built list.
sealed class _Line {}

final class _Head extends _Line {
  _Head(this.group, {required this.fresh});
  final InboxGroup group;
  final bool fresh;
}

final class _Tiles extends _Line {
  _Tiles(this.records);
  final List<TransferRecord> records;
}

final class _FileLine extends _Line {
  _FileLine(this.record, {required this.first});
  final TransferRecord record;
  final bool first;
}

class _InboxPageState extends State<InboxPage> {
  static const _columns = 4;
  bool _selecting = false;
  final Set<int> _selected = {};
  bool _active = true;

  /// What counted as seen when this visit began: groups after it get a dot
  /// for the whole visit, and leaving marks everything seen.
  late DateTime _seenAt;

  @override
  void initState() {
    super.initState();
    _seenAt = context.read<InboxCubit>().seenAt.value;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = ShellTab.isActive(context);
    if (active == _active) return;
    final cubit = context.read<InboxCubit>();
    if (!active) {
      cubit.markSeen();
      if (_selecting) _stopSelecting();
    } else {
      _seenAt = cubit.seenAt.value;
    }
    _active = active;
  }

  @override
  void deactivate() {
    // Switching to the History segment also counts as leaving.
    if (_active) context.read<InboxCubit>().markSeen();
    super.deactivate();
  }

  void _stopSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _toggle(TransferRecord r) => setState(() {
    if (!_selected.remove(r.id)) _selected.add(r.id);
  });

  void _press(TransferRecord r) {
    if (_selecting) return _toggle(r);
    openReceived(context, r);
  }

  void _longPress(TransferRecord r) {
    if (_selecting) return _toggle(r);
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(r.id);
    });
  }

  List<_Line> _lines(List<InboxGroup> groups) {
    final lines = <_Line>[];
    for (final g in groups) {
      lines.add(_Head(g, fresh: g.newest.isAfter(_seenAt)));
      final media = g.media;
      for (var i = 0; i < media.length; i += _columns) {
        lines.add(
          _Tiles(media.sublist(i, (i + _columns).clamp(0, media.length))),
        );
      }
      final files = g.files;
      for (var i = 0; i < files.length; i++) {
        lines.add(_FileLine(files[i], first: i == 0));
      }
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: BlocBuilder<InboxCubit, List<TransferRecord>>(
          builder: (context, items) {
            // A deleted file leaves the selection with it.
            _selected.removeWhere((id) => !items.any((r) => r.id == id));
            final picked = items
                .where((r) => _selected.contains(r.id))
                .toList();
            final bytes = items.fold<int>(0, (s, r) => s + r.fileSize);
            return Stack(
              children: [
                AppResponsivePane(
                  maxWidth: 760,
                  child: Column(
                    children: [
                      if (items.isNotEmpty)
                        _Summary(
                          text: [
                            'inbox.n_files_received'.plural(items.length),
                            formatBytes(bytes),
                          ].join(' · '),
                          action: _selecting
                              ? 'inbox.done'.tr()
                              : 'compose.select'.tr(),
                          onAction: _selecting
                              ? _stopSelecting
                              : () => setState(() => _selecting = true),
                        ),
                      Expanded(
                        child: items.isEmpty
                            ? const _Ready()
                            : _list(context, groupReceived(items)),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AppSelectionBar(
                    visible: _selecting,
                    onClear: _stopSelecting,
                    // Select all lives here, not in the header, so the
                    // header keeps one height in every language.
                    onSummaryTap: () => setState(() {
                      if (picked.length == items.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(items.map((r) => r.id));
                      }
                    }),
                    summary: AppSelectionSummary(
                      title: picked.isEmpty
                          ? 'inbox.select_files'.tr()
                          : 'inbox.n_selected'.tr(
                              namedArgs: {'count': '${picked.length}'},
                            ),
                      subtitle: picked.length == items.length
                          ? 'inbox.select_none'.tr()
                          : 'inbox.select_all'.tr(),
                    ),
                    actions: [
                      if (InboxCubit.canSaveToPhotos)
                        AppBarAction(
                          icon: AppIcons.imageDown,
                          label: 'inbox.save'.tr(),
                          enabled: picked.any(isMedia),
                          onTap: () async {
                            await savePhotos(context, picked);
                            _stopSelecting();
                          },
                        ),
                      AppBarAction(
                        icon: AppIcons.shareLink,
                        label: 'inbox.share'.tr(),
                        enabled: picked.isNotEmpty,
                        onTap: () => shareReceived(picked),
                      ),
                      AppBarAction(
                        icon: AppIcons.trashDelete,
                        label: 'inbox.delete'.tr(),
                        enabled: picked.isNotEmpty,
                        onTap: () async {
                          if (await deleteReceived(context, picked)) {
                            _stopSelecting();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<InboxGroup> groups) {
    final lines = _lines(groups);
    final locale = context.locale.toLanguageTag();
    return CustomScrollView(
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 120),
          sliver: SliverList.builder(
            itemCount: lines.length,
            itemBuilder: (context, i) => switch (lines[i]) {
              _Head(:final group, :final fresh) => _GroupHead(
                group: group,
                fresh: fresh,
                locale: locale,
              ),
              _Tiles(:final records) => _TilesRow(
                records: records,
                columns: _columns,
                selecting: _selecting,
                selected: _selected,
                onTap: _press,
                onLongPress: _longPress,
              ),
              _FileLine(:final record, :final first) => _FileRow(
                record: record,
                first: first,
                selecting: _selecting,
                selected: _selected.contains(record.id),
                locale: locale,
                onTap: () => _press(record),
                onLongPress: () => _longPress(record),
              ),
            },
          ),
        ),
      ],
    );
  }
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({
    required this.group,
    required this.fresh,
    required this.locale,
  });

  final InboxGroup group;
  final bool fresh;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 14, 8),
      child: Row(
        children: [
          if (fresh) ...[
            Semantics(
              label: 'inbox.new'.tr(),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              'inbox.group_title'.tr(
                namedArgs: {
                  'day': dayLabel(group.newest, locale),
                  'alias': group.alias,
                },
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(fontSize: 14, color: t.text),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            [
              'inbox.n_files'.plural(group.records.length),
              timeLabel(group.newest, locale),
            ].join(' · '),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
        ],
      ),
    );
  }
}

class _TilesRow extends StatelessWidget {
  const _TilesRow({
    required this.records,
    required this.columns,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final List<TransferRecord> records;
  final int columns;
  final bool selecting;
  final Set<int> selected;
  final ValueChanged<TransferRecord> onTap;
  final ValueChanged<TransferRecord> onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 2.0;
        final side = (c.maxWidth - gap * (columns - 1)) / columns;
        final px = (side * MediaQuery.devicePixelRatioOf(context)).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: gap),
          child: Row(
            children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                SizedBox.square(
                  dimension: side,
                  child: i < records.length
                      ? AppMediaTile(
                          image: _Thumb(record: records[i], px: px),
                          semanticLabel: shownName(records[i]),
                          selectable: selecting,
                          selected: selected.contains(records[i].id),
                          onTap: () => onTap(records[i]),
                          onLongPress: () => onLongPress(records[i]),
                        )
                      : ColoredBox(color: t.bg),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A received photo at tile size, or a video's first frame. A file that is
/// gone (or not a picture after all) shows its kind instead.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.record, required this.px});

  final TransferRecord record;
  final int px;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final path = record.savedPath;
    Widget glyph() => ColoredBox(
      color: t.sunken,
      child: Center(
        child: AppSvgIcon(
          fileIcon(record.fileType ?? ''),
          size: 24,
          color: t.text2,
        ),
      ),
    );
    if (path == null) return glyph();
    if (isImage(record)) {
      return Hero(
        tag: record.id,
        child: Image(
          image: ResizeImage(
            FileImage(File(path)),
            width: px,
            policy: ResizeImagePolicy.fit,
          ),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => glyph(),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaThumb(
          path: path,
          mime: record.fileType,
          size: px.toDouble(),
          radius: 0,
        ),
        const Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Padding(
            padding: EdgeInsets.all(6),
            child: AppSvgIcon(AppIcons.play, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.record,
    required this.first,
    required this.selecting,
    required this.selected,
    required this.locale,
    required this.onTap,
    required this.onLongPress,
  });

  final TransferRecord record;
  final bool first;
  final bool selecting;
  final bool selected;
  final String locale;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final r = record;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first) const AppRowDivider(indent: 72),
        Material(
          color: selected ? t.accentSoft : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.sunken,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: AppSvgIcon(
                        fileIcon(r.fileType ?? ''),
                        size: 22,
                        color: t.text,
                      ),
                    ),
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
                              formatBytes(r.fileSize),
                              timeLabel(r.timestamp, locale),
                            ].join(' · '),
                            style: AppType.secondary.copyWith(color: t.text2),
                          ),
                        ],
                      ),
                    ),
                    if (selecting) ...[
                      const SizedBox(width: 10),
                      AppRowCheck(selected: selected),
                    ] else if (r.encrypted) ...[
                      const SizedBox(width: 10),
                      Semantics(
                        label: 'receive.encrypted'.tr(),
                        child: AppSvgIcon(
                          AppIcons.passwordLock,
                          size: 15,
                          color: t.ok,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// No files yet: this device, ready to receive, and the two ways that do not
/// need someone nearby. Hidden, it offers to become visible instead.
class _Ready extends StatelessWidget {
  const _Ready();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final settings = context.select<SettingsCubit, s.Settings>((c) => c.state);
    final visible = settings.visibility != s.Visibility.hidden;
    final name = settings.alias;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 120),
      child: Column(
        children: [
          RepaintBoundary(
            child: SizedBox.square(
              dimension: 120,
              child: CustomPaint(
                painter: _Rings(color: visible ? t.accent : t.text3),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: t.line),
                        ),
                        child: AppSvgIcon(
                          iconForDevice(isDesktop ? 'desktop' : 'mobile'),
                          size: 32,
                          color: t.text,
                        ),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: visible ? t.ok : t.text3,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.bg, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            (visible ? 'inbox.ready_title' : 'inbox.hidden_title').tr(
              namedArgs: {'name': name},
            ),
            textAlign: TextAlign.center,
            style: AppType.sheetTitle.copyWith(color: t.text),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              (visible ? 'inbox.ready_body' : 'inbox.hidden_body').tr(
                namedArgs: {'name': name},
              ),
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: t.text2),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: visible
                ? [
                    if (supportsCameraScan)
                      AppButton(
                        label: 'inbox.receive_code'.tr(),
                        size: AppButtonSize.large,
                        onPressed: () => context.push('/scan'),
                      ),
                    AppButton(
                      label: 'inbox.browser_access'.tr(),
                      variant: supportsCameraScan
                          ? AppButtonVariant.secondary
                          : AppButtonVariant.primary,
                      size: AppButtonSize.large,
                      onPressed: () => showWebAccess(context),
                    ),
                  ]
                : [
                    AppButton(
                      label: 'inbox.turn_visible'.tr(),
                      size: AppButtonSize.large,
                      onPressed: () => context
                          .read<SettingsCubit>()
                          .setVisibility(s.Visibility.everyone),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// Two still rings around the device: "nearby can see you", without a loop.
class _Rings extends CustomPainter {
  _Rings({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    paint.color = color.withValues(alpha: 0.35);
    canvas.drawCircle(c, 44, paint);
    paint.color = color.withValues(alpha: 0.16);
    canvas.drawCircle(c, 58, paint);
  }

  @override
  bool shouldRepaint(_Rings old) => old.color != color;
}

/// The Inbox menu (the ⋯ of the Inbox tab on Received): browse files,
/// browser access, save all media, clear.
Future<void> showInboxMenu(BuildContext context) {
  final cubit = context.read<InboxCubit>();
  final items = cubit.state;
  return showAppSheet<void>(
    context,
    title: 'inbox.title'.tr(),
    builder: (ctx) {
      void close() => Navigator.of(ctx).pop();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetGroup(
            children: [
              AppSheetAction(
                icon: AppIcons.folder,
                label: 'inbox.browse_files'.tr(),
                subtitle: 'inbox.browse_files_hint'.tr(),
                onTap: () {
                  close();
                  context.push('/files');
                },
              ),
              AppSheetAction(
                icon: AppIcons.globePublic,
                label: 'inbox.browser_access'.tr(),
                subtitle: 'inbox.browser_access_subtitle'.tr(),
                onTap: () {
                  close();
                  showWebAccess(context);
                },
              ),
              if (InboxCubit.canSaveToPhotos && items.any(isMedia))
                AppSheetAction(
                  icon: AppIcons.imageDown,
                  label: 'inbox.save_all_media'.tr(),
                  onTap: () {
                    close();
                    savePhotos(context, items);
                  },
                ),
            ],
          ),
          if (items.isNotEmpty)
            AppSheetGroup(
              children: [
                AppSheetAction(
                  icon: AppIcons.trashDelete,
                  label: 'inbox.clear_inbox'.tr(),
                  destructive: true,
                  onTap: () async {
                    close();
                    final yes = await showAppConfirm(
                      context,
                      title: 'inbox.clear_title'.tr(),
                      message: 'inbox.clear_body'.tr(),
                      confirmLabel: 'inbox.clear'.tr(),
                    );
                    if (yes) await cubit.deleteMany(List.of(items));
                  },
                ),
              ],
            ),
        ],
      );
    },
  );
}

/// Over the received files: how many and how big, and Select or Done.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 6, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppType.secondary.copyWith(
                color: t.text2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          AppButton(
            label: action,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}
