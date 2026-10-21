import 'dart:math';

import '../../../core/storage/app_database.dart';
import 'vault_uploader.dart';

/// The uploads of one go, for a progress bar that moves one way (owner
/// 2026-10-21: the bar "naik turun tidak teratur"). A go runs from the
/// oldest upload still waiting or sending, and keeps the uploads that
/// finished since then: a file that finishes does not leave the count.
/// Each file weighs its size; the one being sent counts what has gone so
/// far.
class UploadBatch {
  const UploadBatch._({
    required this.start,
    required this.running,
    required this.files,
    required this.filesDone,
    required this.bytes,
    required this.bytesDone,
    required this.stopped,
    this.current,
  });

  /// When the go began: the same while it lasts, a new one after.
  final int start;

  final List<VaultTransfer> running;
  final int files;
  final int filesDone;
  final int bytes;
  final int bytesDone;

  /// Uploads that stopped with an error (not part of the go).
  final int stopped;

  /// The upload being sent now, or the next in line.
  final VaultTransfer? current;

  double? get fraction => bytes > 0 ? min(1, bytesDone / bytes) : null;

  static bool _isRunning(VaultTransfer t) =>
      t.direction == 'up' &&
      t.state != 'done' &&
      t.state != 'failed' &&
      t.state != 'cancelled';

  /// Null when nothing is going up.
  static UploadBatch? of(List<VaultTransfer> all, VaultUploader uploader) {
    final running = all.where(_isRunning).toList();
    final stopped = all
        .where((t) => t.direction == 'up' && t.state == 'failed')
        .length;
    if (running.isEmpty) {
      return stopped == 0
          ? null
          : UploadBatch._(
              start: 0,
              running: const [],
              files: 0,
              filesDone: 0,
              bytes: 0,
              bytesDone: 0,
              stopped: stopped,
            );
    }
    final start = running.map((t) => t.createdAt).reduce(min);
    final done = [
      for (final t in all)
        if (t.direction == 'up' && t.state == 'done' && t.updatedAt >= start) t,
    ];
    var bytes = 0;
    var sent = 0.0;
    VaultTransfer? current;
    for (final t in done) {
      bytes += t.size;
      sent += t.size;
    }
    for (final t in running) {
      bytes += t.size;
      final p = uploader.progressOf(t.id);
      if (p != null) {
        current = t;
        if (p.total > 0) sent += t.size * min(1, p.done / p.total);
      }
    }
    current ??= running.reduce((a, b) => a.createdAt <= b.createdAt ? a : b);
    return UploadBatch._(
      start: start,
      running: running,
      files: done.length + running.length,
      filesDone: done.length,
      bytes: bytes,
      bytesDone: sent.round(),
      stopped: stopped,
      current: current,
    );
  }
}

/// Keeps a bar from going back within one go: files joining a go (photo
/// backup adds them a few dozen at a time) raise the total, and the bar
/// waits for the sent bytes to catch up instead of dropping.
class OneWayProgress {
  int? _start;
  double _shown = 0;

  double? of(UploadBatch? batch) {
    final f = batch?.fraction;
    if (batch == null || f == null) {
      _start = null;
      _shown = 0;
      return null;
    }
    if (batch.start != _start) {
      _start = batch.start;
      _shown = f;
    } else {
      _shown = max(_shown, f);
    }
    return _shown;
  }
}
