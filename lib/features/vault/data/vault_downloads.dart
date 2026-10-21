import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import 'vault_downloader.dart';

enum VaultJobState { running, done, failed, cancelled }

/// One file (or folder) coming back from the Drive, for the Transfers screen.
class VaultDownloadJob {
  VaultDownloadJob._(this.id, this.name, this.isFolder, this.target);

  final int id;
  final String name;
  final bool isFolder;

  /// Where the file (or the folder) lands.
  final String target;

  VaultJobState state = VaultJobState.running;
  int done = 0;
  int total = 0;

  /// Folders: files finished of all.
  int filesDone = 0;
  int filesTotal = 0;
  Object? error;
  final CancelToken cancel = CancelToken();

  double? get fraction => total > 0 ? done / total : null;
}

/// Downloads started from the Drive screens (task 4.5's downloader with a
/// list around it): progress, cancel, whole folders, and the cache folders
/// that "Open" and "Share" use. Not persisted: a download is quick to start
/// again, unlike an upload.
class VaultDownloads extends ChangeNotifier {
  VaultDownloads({required VaultDownloader downloader, required VaultDao dao})
    : _downloader = downloader,
      _dao = dao;

  final VaultDownloader _downloader;
  final VaultDao _dao;
  final List<VaultDownloadJob> _jobs = [];
  int _next = 0;

  List<VaultDownloadJob> get jobs => List.unmodifiable(_jobs.reversed);

  bool get busy => _jobs.any((j) => j.state == VaultJobState.running);

  /// The cache folder for files opened or shared from the Drive.
  static Future<Directory> cacheFor(String purpose, String objectId) async =>
      Directory(
        '${(await getTemporaryDirectory()).path}/vault-$purpose/$objectId',
      );

  /// Download one file to [target]. Null when cancelled or failed (the job
  /// keeps the error).
  Future<File?> file(VaultObject o, File target, {bool listed = true}) async {
    final job = VaultDownloadJob._(_next++, o.name, false, target.path)
      ..total = o.blobSize ?? o.size ?? 0;
    if (listed) _add(job);
    try {
      final f = await _downloader.download(
        o.id,
        target,
        cancel: job.cancel,
        onProgress: (d, t) {
          job
            ..done = d
            ..total = t > 0 ? t : job.total;
          notifyListeners();
        },
      );
      job.state = VaultJobState.done;
      return f;
    } on Object catch (e) {
      job
        ..state = job.cancel.isCancelled
            ? VaultJobState.cancelled
            : VaultJobState.failed
        ..error = e;
      if (await target.exists() && job.state != VaultJobState.done) {
        try {
          await target.delete();
        } on Object {
          // Partial file; the cache is cleared anyway.
        }
      }
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Download folder [dir] with everything in it into a folder of its name
  /// inside [into]; a name already there gets " (1)", " (2)", … so nothing
  /// on the computer is replaced.
  /// Returns the folder made, or null when cancelled or something failed.
  Future<Directory?> folder(VaultObject dir, Directory into) async {
    final root = Directory(
      '${into.path}${Platform.pathSeparator}${await _freeDirName(into, safeName(dir.name))}',
    );
    final plan = <(VaultObject, String)>[];
    final seen = <String>{dir.id};
    Future<void> walk(VaultObject d, String path) async {
      // Two siblings can share a name in the Drive; not on disk.
      final used = <String>{};
      for (final c in await _dao.childrenOf(d.id)) {
        if (c.trashedAt != null || !seen.add(c.id)) continue;
        final name = _unique(safeName(c.name), used);
        final at = '$path${Platform.pathSeparator}$name';
        if (c.kind == 'dir') {
          await walk(c, at);
        } else {
          plan.add((c, at));
        }
      }
    }

    await walk(dir, root.path);
    final job = VaultDownloadJob._(_next++, dir.name, true, root.path)
      ..filesTotal = plan.length
      ..total = plan.fold<int>(0, (s, e) => s + (e.$1.blobSize ?? 0));
    _add(job);
    await root.create(recursive: true);
    var before = 0;
    try {
      for (final (o, path) in plan) {
        if (job.cancel.isCancelled) break;
        await Directory(File(path).parent.path).create(recursive: true);
        await _downloader.download(
          o.id,
          File(path),
          cancel: job.cancel,
          onProgress: (d, _) {
            job.done = before + d;
            notifyListeners();
          },
        );
        before += o.blobSize ?? 0;
        job.filesDone++;
        notifyListeners();
      }
      job.state = job.cancel.isCancelled
          ? VaultJobState.cancelled
          : VaultJobState.done;
    } on Object catch (e) {
      job
        ..state = job.cancel.isCancelled
            ? VaultJobState.cancelled
            : VaultJobState.failed
        ..error = e;
    } finally {
      notifyListeners();
    }
    return job.state == VaultJobState.done ? root : null;
  }

  void cancel(VaultDownloadJob job) {
    if (job.state == VaultJobState.running) job.cancel.cancel();
  }

  void clearFinished() {
    _jobs.removeWhere((j) => j.state != VaultJobState.running);
    notifyListeners();
  }

  void _add(VaultDownloadJob job) {
    _jobs.add(job);
    if (_jobs.length > 50) _jobs.removeAt(0);
    notifyListeners();
  }

  /// Sign-out: files opened from the Drive go from the cache.
  Future<void> clearCache() async {
    final tmp = await getTemporaryDirectory();
    for (final name in ['vault-open', 'vault-save', 'vault-get']) {
      final d = Directory('${tmp.path}/$name');
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } on Object {
        // The system clears it eventually.
      }
    }
    _jobs.clear();
    notifyListeners();
  }

  /// [name] as a file name on any system: no folder separators, no
  /// characters Windows refuses, never "." or "..".
  static String safeName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_')
        .trim();
    if (cleaned.isEmpty) return 'file';
    if (RegExp(r'^\.+$').hasMatch(cleaned)) return '_';
    return cleaned;
  }

  /// [name], or "name (1)", "name (2)", … when [used] has it (any case).
  static String _unique(String name, Set<String> used) {
    var out = name;
    final dot = name.lastIndexOf('.');
    final (stem, ext) = dot > 0
        ? (name.substring(0, dot), name.substring(dot))
        : (name, '');
    for (var n = 1; used.contains(out.toLowerCase()); n++) {
      out = '$stem ($n)$ext';
    }
    used.add(out.toLowerCase());
    return out;
  }

  static Future<String> _freeDirName(Directory into, String name) async {
    var out = name;
    for (
      var n = 1;
      await FileSystemEntity.type(
            '${into.path}${Platform.pathSeparator}$out',
          ) !=
          FileSystemEntityType.notFound;
      n++
    ) {
      out = '$name ($n)';
    }
    return out;
  }
}
