import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/locator.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../inbox/domain/inbox_groups.dart';
import '../data/file_scanner.dart';
import '../domain/managed_file.dart';
import 'widgets/storage_bar.dart';

/// Browse files (redesign-plan.md 5.4): scans the receive directory, groups
/// by folder, sender or date, searches and sorts, shows the storage split,
/// and opens, shares or deletes (tap, long press, or swipe).
class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  List<ManagedFile> _all = const [];
  GroupMode _group = GroupMode.category;
  SortMode _sort = SortMode.newest;
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dir = getIt<TransferServer>().saveDirectory;
    final received = await getIt<AppDatabase>().receivedRecords();
    final files = await FileScanner.scan(dir, received);
    if (!mounted) return;
    setState(() {
      _all = files;
      _loading = false;
    });
  }

  List<ManagedFile> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = _all.where((f) {
      return q.isEmpty ||
          f.name.toLowerCase().contains(q) ||
          f.sender.toLowerCase().contains(q);
    }).toList();
    list.sort(switch (_sort) {
      SortMode.newest => (a, b) => b.modified.compareTo(a.modified),
      SortMode.oldest => (a, b) => a.modified.compareTo(b.modified),
      SortMode.largest => (a, b) => b.size.compareTo(a.size),
      SortMode.name => (a, b) => _shown(
        a,
      ).toLowerCase().compareTo(_shown(b).toLowerCase()),
    });
    return list;
  }

  Map<String, List<ManagedFile>> _grouped(String locale) {
    final map = <String, List<ManagedFile>>{};
    for (final f in _filtered) {
      final key = switch (_group) {
        GroupMode.category => categoryLabel(f.category),
        GroupMode.sender => _sender(f),
        GroupMode.date => _dateKey(f.modified, locale),
      };
      (map[key] ??= []).add(f);
    }
    return map;
  }

  Future<void> _delete(ManagedFile f) async {
    final file = File(f.path);
    if (file.existsSync()) {
      try {
        await file.delete();
      } on FileSystemException {
        // ignore
      }
    }
    if (f.recordId != null) {
      await getIt<AppDatabase>().deleteRecord(f.recordId!);
    }
    if (!mounted) return;
    setState(() => _all = _all.where((x) => x.path != f.path).toList());
  }

  Future<bool> _confirmDelete(ManagedFile f) => showAppConfirm(
    context,
    title: 'inbox.delete_n_title'.plural(1),
    message: 'inbox.delete_body'.tr(),
    confirmLabel: 'inbox.delete'.tr(),
  );

  Future<void> _sortSheet() {
    return showAppSheet<void>(
      context,
      title: 'files.sort'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in SortMode.values)
            _SortRow(
              label: s.label,
              chosen: s == _sort,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _sort = s);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final locale = context.locale.toLanguageTag();
    final groups = _grouped(locale);
    final totalBytes = _all.fold<int>(0, (s, f) => s + f.size);
    final ready = !_loading && _all.isNotEmpty;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 760,
          child: Column(
            children: [
              AppScreenHeader(
                title: 'files.title'.tr(),
                onBack: () => Navigator.pop(context),
                actions: [
                  if (ready)
                    AppIconButton(
                      icon: AppIcons.sort,
                      tooltip: 'files.sort'.tr(),
                      onPressed: _sortSheet,
                    ),
                  AppIconButton(
                    icon: AppIcons.refreshSync,
                    tooltip: 'files.refresh'.tr(),
                    onPressed: _load,
                  ),
                ],
              ),
              if (ready) ...[
                AppSearchField(
                  hint: 'files.search'.tr(),
                  onChanged: (q) => setState(() => _query = q),
                ),
                AppSegmented<GroupMode>(
                  value: _group,
                  options: [for (final g in GroupMode.values) (g, g.label)],
                  onChanged: (g) => setState(() => _group = g),
                  margin: const EdgeInsets.fromLTRB(14, 6, 14, 2),
                ),
              ],
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _all.isEmpty
                    ? AppEmptyState(
                        icon: AppIcons.folderOpen,
                        title: 'files.no_files'.tr(),
                        message: 'files.no_files_message'.tr(),
                      )
                    : groups.isEmpty
                    ? AppEmptyState(
                        icon: AppIcons.search,
                        title: 'history.empty_no_matches_title'.tr(),
                        message: 'files.no_matches'.tr(),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 28),
                        children: [
                          StorageBar(files: _all, totalBytes: totalBytes),
                          for (final MapEntry(:key, :value)
                              in groups.entries) ...[
                            _GroupHead(label: key, files: value),
                            for (var i = 0; i < value.length; i++)
                              _Row(
                                file: value[i],
                                first: i == 0,
                                shown: _shown(value[i]),
                                meta: _meta(value[i], locale),
                                onOpen: _open,
                                onShare: _share,
                                onDelete: _delete,
                                confirmDelete: _confirmDelete,
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sender(ManagedFile f) =>
      f.sender.isEmpty ? 'files.unknown_sender'.tr() : f.sender;

  String _shown(ManagedFile f) => shownFileName(f.name, f.sender);

  /// Size, then what the group does not already say.
  String _meta(ManagedFile f, String locale) => [
    formatBytes(f.size),
    if (_group != GroupMode.sender) _sender(f),
    if (_group == GroupMode.date)
      timeLabel(f.modified, locale)
    else
      dayLabel(f.modified, locale),
  ].join(' · ');

  Future<void> _open(ManagedFile f) => showFilePreview(
    context,
    path: f.path,
    name: f.name,
    mimeType:
        f.fileType ?? lookupMimeType(f.name) ?? 'application/octet-stream',
    size: f.size,
  );

  Future<void> _share(ManagedFile f) =>
      SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));

  static String _dateKey(DateTime t, String locale) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'compose.today'.tr();
    if (diff == 1) return 'compose.yesterday'.tr();
    if (diff < 7) return 'files.this_week'.tr();
    return DateFormat.yMMMM(locale).format(t);
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      selected: chosen,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppType.row.copyWith(
                    color: t.text,
                    fontWeight: chosen ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (chosen) AppSvgIcon(AppIcons.check, size: 20, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHead extends StatelessWidget {
  const _GroupHead({required this.label, required this.files});

  final String label;
  final List<ManagedFile> files;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bytes = files.fold<int>(0, (s, f) => s + f.size);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(fontSize: 14, color: t.text),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'receive.n_files_size'.plural(
              files.length,
              namedArgs: {'size': formatBytes(bytes)},
            ),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.file,
    required this.first,
    required this.shown,
    required this.meta,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
    required this.confirmDelete,
  });

  final ManagedFile file;
  final bool first;
  final String shown;
  final String meta;
  final ValueChanged<ManagedFile> onOpen;
  final ValueChanged<ManagedFile> onShare;
  final Future<void> Function(ManagedFile) onDelete;
  final Future<bool> Function(ManagedFile) confirmDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f = file;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first) const AppRowDivider(indent: 72),
        Dismissible(
          key: ValueKey(f.path),
          direction: DismissDirection.endToStart,
          background: Container(
            color: t.danger,
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.only(end: 22),
            child: AppSvgIcon(AppIcons.trashDelete, color: t.onDanger),
          ),
          confirmDismiss: (_) => confirmDelete(f),
          onDismissed: (_) => onDelete(f),
          child: AppRowMenu(
            title: shown,
            subtitle: meta,
            actions: [
              AppMenuAction(
                icon: AppIcons.externalLink,
                label: 'common.open'.tr(),
                onTap: () => onOpen(f),
              ),
              AppMenuAction(
                icon: AppIcons.shareLink,
                label: 'common.share'.tr(),
                onTap: () => onShare(f),
              ),
              AppMenuAction(
                icon: AppIcons.trashDelete,
                label: 'common.delete'.tr(),
                destructive: true,
                onTap: () async {
                  if (await confirmDelete(f)) await onDelete(f);
                },
              ),
            ],
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onOpen(f),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        MediaThumb(path: f.path, mime: f.fileType, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shown,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.row.copyWith(color: t.text),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.secondary.copyWith(
                                  color: t.text2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (f.encrypted) ...[
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
          ),
        ),
      ],
    );
  }
}
