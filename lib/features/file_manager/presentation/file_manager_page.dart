import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/server/transfer_server.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../data/file_scanner.dart';
import '../domain/managed_file.dart';
import 'widgets/file_row.dart';
import 'widgets/group_bar.dart';
import 'widgets/header.dart';
import 'widgets/storage_bar.dart';

/// The File Manager: scans the receive directory, groups + sorts + searches,
/// shows a storage breakdown, and supports open / share / delete.
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
      SortMode.name => (a, b) => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
    });
    return list;
  }

  Map<String, List<ManagedFile>> get _grouped {
    final map = <String, List<ManagedFile>>{};
    for (final f in _filtered) {
      final key = switch (_group) {
        GroupMode.category => f.category,
        GroupMode.sender => f.sender,
        GroupMode.date => _dateKey(f.modified),
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
    setState(() => _all = _all.where((x) => x.path != f.path).toList());
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final groups = _grouped;
    final totalBytes = _all.fold<int>(0, (s, f) => s + f.size);
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 760,
          child: Column(
            children: [
              Header(onBack: () => Navigator.pop(context), onRefresh: _load),
              if (!_loading && _all.isNotEmpty)
                StorageBar(files: _all, totalBytes: totalBytes),
              if (!_loading && _all.isNotEmpty) ...[
                GroupBar(
                  value: _group,
                  onChanged: (g) => setState(() => _group = g),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: ShadInput(
                          placeholder: Text('files.search'.tr()),
                          leading: const AppSvgIcon(AppIcons.search, size: 16),
                          onChanged: (q) => setState(() => _query = q),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ShadSelect<SortMode>(
                        initialValue: _sort,
                        minWidth: 120,
                        selectedOptionBuilder: (context, v) => Text(v.label),
                        options: [
                          for (final s in SortMode.values)
                            ShadOption(value: s, child: Text(s.label)),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _sort = v);
                        },
                      ),
                    ],
                  ),
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
                    : ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 28),
                        children: [
                          for (final key in groups.keys) ...[
                            AppSectionHeader(
                              key,
                              trailing: Text('${groups[key]!.length}'),
                            ),
                            AppGroup(
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < groups[key]!.length;
                                    i++
                                  ) ...[
                                    if (i > 0) const AppRowDivider(indent: 62),
                                    FileRow(
                                      file: groups[key]![i],
                                      onOpen: _open,
                                      onShare: _share,
                                      onDelete: _delete,
                                    ),
                                  ],
                                ],
                              ),
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

  Future<void> _open(ManagedFile f) async {
    if (!await openFile(f.path) && mounted) {
      toast(context, 'common.no_app_open'.tr(), type: ToastType.error);
    }
  }

  Future<void> _share(ManagedFile f) =>
      SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));

  static String _dateKey(DateTime t) {
    final now = DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${p2(t.month)}';
  }
}
