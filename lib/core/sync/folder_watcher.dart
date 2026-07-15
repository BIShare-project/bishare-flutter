import 'dart:async';

import 'package:watcher/watcher.dart';

/// Debounced filesystem watching for one sync-pair root (§4.2).
///
/// `package:watcher` picks the platform mechanism (FSEvents / inotify with
/// recursion handling / ReadDirectoryChangesW, polling where none exists) and
/// this wrapper collapses event bursts — a save that touches dozens of files
/// (editors, unzips, builds) becomes ONE "changed" signal after [debounce] of
/// quiet. The engine's own rescan + stability check decide what actually moved;
/// the watcher only answers "did anything happen?", so dropped/coalesced events
/// are harmless (the periodic full rescan is the backstop for missed ones).
class FolderWatcher {
  FolderWatcher(
    this.rootPath, {
    this.debounce = const Duration(milliseconds: 500),
    DirectoryWatcher Function(String path)? factory,
  }) : _factory = factory ?? DirectoryWatcher.new;

  final String rootPath;
  final Duration debounce;
  final DirectoryWatcher Function(String path) _factory;

  final _changed = StreamController<void>.broadcast();
  StreamSubscription<WatchEvent>? _sub;
  Timer? _pending;
  bool _running = false;

  /// One event per quiet-period after a burst of filesystem changes.
  Stream<void> get changes => _changed.stream;

  bool get isRunning => _running;

  void start() {
    if (_running) return;
    _running = true;
    final watcher = _factory(rootPath);
    _sub = watcher.events.listen(
      (_) => _bump(),
      // A watcher error (root unmounted, inotify limit) silences THIS signal
      // only — the periodic rescan still syncs; a later start() re-arms.
      onError: (Object _) => stop(),
      onDone: stop,
    );
  }

  void _bump() {
    _pending?.cancel();
    _pending = Timer(debounce, () {
      if (!_changed.isClosed) _changed.add(null);
    });
  }

  void stop() {
    _running = false;
    _pending?.cancel();
    _pending = null;
    unawaited(_sub?.cancel());
    _sub = null;
  }

  Future<void> dispose() async {
    stop();
    await _changed.close();
  }
}
