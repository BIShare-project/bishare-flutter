import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../../core/apps/installed_apps_channel.dart';
import '../data/send_media_library.dart';
import '../domain/sendable_file.dart';
import 'tray_cubit.dart';

/// The Send tab a selected item counts under.
enum SendKind { photo, video, audio, app, doc, more }

/// One selected item. A gallery photo or an app stays a reference until the
/// moment of sending ([SendSelectionCubit.materialize]); a file is already
/// staged in the [TrayCubit].
sealed class SendEntry {
  const SendEntry();

  String get key;
  SendKind get kind;

  /// Bytes, when known (unknown for an iOS photo until it is exported).
  int? get size;
}

final class AssetEntry extends SendEntry {
  const AssetEntry(this.asset, this.kind, {this.size});

  final AssetEntity asset;
  @override
  final SendKind kind;
  @override
  final int? size;

  @override
  String get key => 'a:${asset.id}';
}

final class AppEntry extends SendEntry {
  const AppEntry(this.app);

  final InstalledApp app;

  @override
  String get key => 'p:${app.packageName}';
  @override
  SendKind get kind => SendKind.app;
  @override
  int get size => app.sizeBytes;
}

final class FileEntry extends SendEntry {
  const FileEntry(this.file, this.kind);

  final SendableFile file;
  @override
  final SendKind kind;

  @override
  String get key => 'f:${file.id}';
  @override
  int get size => file.size;
}

/// What is selected on the Send tab, in the order it was picked.
class SendSelection {
  const SendSelection([this.entries = const []]);

  final List<SendEntry> entries;

  int get length => entries.length;
  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// 1-based pick order of [key], or null when not selected.
  int? orderOf(String key) {
    final i = entries.indexWhere((e) => e.key == key);
    return i < 0 ? null : i + 1;
  }

  bool contains(String key) => entries.any((e) => e.key == key);

  /// 1-based pick order of the staged file at [path], or null.
  int? orderOfPath(String path) {
    final i = entries.indexWhere((e) => e is FileEntry && e.file.path == path);
    return i < 0 ? null : i + 1;
  }

  int countOf(SendKind kind) => entries.where((e) => e.kind == kind).length;

  /// Total bytes, or null while any size is unknown.
  int? get bytes {
    var sum = 0;
    for (final e in entries) {
      final s = e.size;
      if (s == null) return null;
      sum += s;
    }
    return sum;
  }
}

/// The Send tab's selection (redesign-plan.md 3.2): one ordered list across
/// every tab. Files staged by the existing pickers, the share sheet or a
/// desktop drop land in [TrayCubit] and are mirrored here; gallery photos and
/// apps are held as references and turned into files only when sending, so
/// selecting never copies anything.
class SendSelectionCubit extends Cubit<SendSelection> {
  SendSelectionCubit(this._tray, {SendMediaLibrary? library})
    : _library = library ?? SendMediaLibrary.instance,
      super(const SendSelection()) {
    _sub = _tray.stream.listen(_syncTray);
    _syncTray(_tray.state);
  }

  final TrayCubit _tray;
  final SendMediaLibrary _library;
  late final StreamSubscription<List<SendableFile>> _sub;
  SendKind? _hint;
  bool _materializing = false;

  /// The tab the next staged files come from (More, for a note).
  void hintNext(SendKind kind) => _hint = kind;

  static SendKind kindOfFile(SendableFile f) {
    final mime = f.mimeType.isEmpty
        ? (lookupMimeType(f.name) ?? '')
        : f.mimeType;
    final name = f.name.toLowerCase();
    if (name.endsWith('.apk') || name.endsWith('.apks')) return SendKind.app;
    if (mime.startsWith('image/')) return SendKind.photo;
    if (mime.startsWith('video/')) return SendKind.video;
    if (mime.startsWith('audio/')) return SendKind.audio;
    if (name.endsWith('.vcf')) return SendKind.more;
    return SendKind.doc;
  }

  void _syncTray(List<SendableFile> files) {
    if (_materializing) return;
    final ids = {for (final f in files) f.id};
    final kept = state.entries
        .where((e) => e is! FileEntry || ids.contains(e.file.id))
        .toList();
    final have = {for (final e in kept.whereType<FileEntry>()) e.file.id};
    final hint = _hint;
    _hint = null;
    for (final f in files) {
      if (!have.contains(f.id)) kept.add(FileEntry(f, hint ?? kindOfFile(f)));
    }
    emit(SendSelection(kept));
  }

  /// Select or unselect one gallery item.
  void toggleAsset(AssetEntity a, SendKind kind) =>
      setAssets([a], kind, !state.contains('a:${a.id}'));

  /// Select (or unselect) several gallery items at once: a day's "Select", a
  /// drag across the grid.
  void setAssets(List<AssetEntity> assets, SendKind kind, bool on) {
    final entries = [...state.entries];
    final added = <AssetEntity>[];
    for (final a in assets) {
      final key = 'a:${a.id}';
      final i = entries.indexWhere((e) => e.key == key);
      if (on && i < 0) {
        entries.add(AssetEntry(a, kind));
        added.add(a);
      } else if (!on && i >= 0) {
        entries.removeAt(i);
      }
    }
    emit(SendSelection(entries));
    for (final a in added) {
      unawaited(_fillSize(a));
    }
  }

  Future<void> _fillSize(AssetEntity a) async {
    final size = await _library.sizeOf(a);
    if (size == null || isClosed) return;
    emit(
      SendSelection([
        for (final e in state.entries)
          if (e is AssetEntry && e.asset.id == a.id)
            AssetEntry(e.asset, e.kind, size: size)
          else
            e,
      ]),
    );
  }

  void toggleApp(InstalledApp app) {
    final key = 'p:${app.packageName}';
    final entries = [...state.entries];
    final i = entries.indexWhere((e) => e.key == key);
    i < 0 ? entries.add(AppEntry(app)) : entries.removeAt(i);
    emit(SendSelection(entries));
  }

  /// Select a file already on disk (a document received earlier), or
  /// unselect it when it is selected.
  void toggleFile(String path, SendKind kind) {
    final existing = _tray.state.where((f) => f.path == path).firstOrNull;
    if (existing != null) {
      _tray.remove(existing);
      return;
    }
    hintNext(kind);
    _tray.addPaths([path]);
  }

  bool isFileSelected(String path) => _tray.state.any((f) => f.path == path);

  void remove(SendEntry e) {
    if (e is FileEntry) {
      _tray.remove(e.file);
      return;
    }
    emit(SendSelection(state.entries.where((x) => x.key != e.key).toList()));
  }

  void clear() {
    _tray.clear();
    emit(const SendSelection());
  }

  /// Turns every reference into a staged file, in the order picked, and
  /// returns the files to send. Gallery originals are exported here (an
  /// iCloud photo downloads), images compressed to the media-quality setting,
  /// apps copied out of the system. [onProgress] counts items done.
  Future<List<SendableFile>> materialize({
    void Function(int done, int total)? onProgress,
  }) async {
    _materializing = true;
    try {
      final out = <SendableFile>[];
      final entries = state.entries;
      for (var i = 0; i < entries.length; i++) {
        switch (entries[i]) {
          case FileEntry(:final file):
            out.add(file);
          case AssetEntry(:final asset):
            final f = await _library.original(asset);
            if (f != null) out.addAll(await _tray.stageMedia([f.path]));
          case AppEntry(:final app):
            out.addAll(await _tray.stageApks([app]));
        }
        onProgress?.call(i + 1, entries.length);
      }
      _tray.reorder([for (final f in out) f.id]);
      emit(SendSelection([for (final f in out) FileEntry(f, kindOfFile(f))]));
      return out;
    } finally {
      _materializing = false;
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
