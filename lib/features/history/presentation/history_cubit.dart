import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_format.dart';
import '../data/history_repository.dart';

/// Which transfers the History screen shows.
enum HistoryFilter {
  all,
  sent,
  received;

  String get label => switch (this) {
    HistoryFilter.all => 'history.all'.tr(),
    HistoryFilter.sent => 'history.sent'.tr(),
    HistoryFilter.received => 'history.received'.tr(),
  };
}

class HistoryState extends Equatable {
  const HistoryState({
    this.all = const [],
    this.filter = HistoryFilter.all,
    this.query = '',
  });

  final List<TransferRecord> all;
  final HistoryFilter filter;
  final String query;

  /// The list after the active filter + search query.
  List<TransferRecord> get filtered {
    final q = query.trim().toLowerCase();
    return all
        .where((r) {
          final matchFilter =
              filter == HistoryFilter.all || r.direction == filter.name;
          final matchSearch =
              q.isEmpty ||
              r.fileName.toLowerCase().contains(q) ||
              r.deviceAlias.toLowerCase().contains(q);
          return matchFilter && matchSearch;
        })
        .toList(growable: false);
  }

  int get sentCount => all.where((r) => r.direction == 'sent').length;
  int get receivedCount => all.where((r) => r.direction == 'received').length;
  int get total => all.length;

  HistoryState copyWith({
    List<TransferRecord>? all,
    HistoryFilter? filter,
    String? query,
  }) => HistoryState(
    all: all ?? this.all,
    filter: filter ?? this.filter,
    query: query ?? this.query,
  );

  @override
  List<Object?> get props => [all, filter, query];
}

/// Drives the History screen over the full transfer log (sent + received).
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit(this._history) : super(const HistoryState()) {
    _sub = _history.watchAll().listen(
      (rows) => emit(state.copyWith(all: rows)),
    );
  }

  final HistoryRepository _history;
  late final StreamSubscription<List<TransferRecord>> _sub;

  void setFilter(HistoryFilter f) => emit(state.copyWith(filter: f));
  void setQuery(String q) => emit(state.copyWith(query: q));

  /// Delete a record and unlink its file on disk (received rows only).
  Future<void> deleteEntry(TransferRecord r) async {
    await _history.delete(r.id);
    await _unlink(r.savedPath);
  }

  /// Clear the whole history and unlink every received file (best-effort).
  Future<void> clearAll() async {
    for (final r in state.all) {
      await _unlink(r.savedPath);
    }
    await _history.clear();
  }

  /// Write the history to a temp CSV and return its path (for the share sheet).
  Future<String> exportCsv() async {
    final buf = StringBuffer()
      ..writeln(
        _csvRow([
          'history.csv_date'.tr(),
          'history.csv_direction'.tr(),
          'history.csv_file'.tr(),
          'history.csv_type'.tr(),
          'history.csv_size'.tr(),
          'history.csv_device'.tr(),
          'history.csv_verified'.tr(),
        ]),
      );
    for (final r in state.all) {
      buf.writeln(
        _csvRow([
          _csvDate(r.timestamp),
          r.direction,
          r.fileName,
          r.fileType ?? '',
          formatBytes(r.fileSize),
          r.deviceAlias,
          r.verified ? 'history.yes'.tr() : 'history.no'.tr(),
        ]),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'BIShare_History.csv'));
    await file.writeAsString(buf.toString());
    return file.path;
  }

  Future<void> _unlink(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (!f.existsSync()) return;
    try {
      await f.delete();
    } on FileSystemException {
      // best-effort — the record is already gone
    }
  }

  static String _csvRow(List<String> fields) =>
      fields.map((f) => '"${f.replaceAll('"', '""')}"').join(',');

  static String _csvDate(DateTime t) {
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${p2(t.month)}-${p2(t.day)} '
        '${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}';
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
