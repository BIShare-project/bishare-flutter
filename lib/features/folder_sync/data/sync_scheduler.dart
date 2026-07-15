import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/storage/app_database.dart';
import '../../../core/storage/sync_tables.dart';
import '../../../core/sync/folder_watcher.dart';
import '../../discovery/domain/discovered_device.dart';

/// Runs one sync toward an online peer — the scheduler's only side effect.
/// Production wraps `SyncEngine.syncNow`; tests inject a recorder.
typedef SyncRunner = Future<void> Function(SyncPair pair, DiscoveredDevice peer);

/// A cloud-path run (push when the peer is away, pull on the poll tick).
/// Production wraps `CloudSyncAdapter`; the adapter self-gates (mode/tier/key),
/// so calling it for an ineligible pair is a cheap no-op.
typedef CloudRunner = Future<void> Function(SyncPair pair);

/// Turns manual folder sync into automatic sync (M2b): one debounced
/// [FolderWatcher] per active pair, a push when a pair's peer (re)appears on
/// the LAN, and a periodic full-rescan backstop for anything a watcher missed.
///
/// Triggers only ever call [SyncEngine.syncNow], which is serialized per pair —
/// overlapping triggers collapse into the existing single-flight chain. Echo
/// behavior is self-limiting: a peer-applied write fires the local watcher, the
/// resulting exchange finds every hash equal (0 needed / 0 applied), nothing is
/// written, and the chain stops — no ping-pong.
class SyncScheduler {
  SyncScheduler(
    this._run,
    this._dao, {
    required Stream<List<DiscoveredDevice>> deviceStream,
    required List<DiscoveredDevice> Function() currentDevices,
    this.rescanEvery = const Duration(hours: 6),
    Duration watcherDebounce = const Duration(milliseconds: 500),
    FolderWatcher Function(String rootPath)? watcherFactory,
    String Function(String stored)? resolveRoot,
    Future<void> Function()? maintenance,
    CloudRunner? cloudPush,
    CloudRunner? cloudPull,
    this.cloudPollEvery = const Duration(seconds: 60),
  })  : _maintenance = maintenance,
        _cloudPush = cloudPush,
        _cloudPull = cloudPull,
        _currentDevices = currentDevices,
        _deviceStream = deviceStream,
        _resolveRoot = resolveRoot ?? ((s) => s),
        _watcherFactory = watcherFactory ??
            ((root) => FolderWatcher(root, debounce: watcherDebounce));

  final SyncRunner _run;
  final SyncDao _dao;
  final Stream<List<DiscoveredDevice>> _deviceStream;
  final List<DiscoveredDevice> Function() _currentDevices;
  final FolderWatcher Function(String rootPath) _watcherFactory;
  final String Function(String stored) _resolveRoot;
  final Future<void> Function()? _maintenance;
  final CloudRunner? _cloudPush;
  final CloudRunner? _cloudPull;
  final Duration rescanEvery;
  final Duration cloudPollEvery;

  final Map<String, FolderWatcher> _watchers = {}; // pairId → watcher
  final Map<String, StreamSubscription<void>> _watcherSubs = {};
  StreamSubscription<List<SyncPair>>? _pairsSub;
  StreamSubscription<List<DiscoveredDevice>>? _deviceSub;
  Timer? _rescanTimer;
  Timer? _cloudPollTimer;
  Set<String> _onlineFps = const {};
  List<SyncPair> _pairs = const [];

  void start() {
    _pairsSub ??= _dao.watchPairs().listen(_onPairs);
    _deviceSub ??= _deviceStream.listen(_onDevices);
    _onlineFps = {for (final d in _currentDevices()) d.fingerprint};
    _rescanTimer ??= Timer.periodic(rescanEvery, (_) {
      // Housekeeping rides the same tick (trash TTL is 30 days — 6h is plenty).
      final sweep = _maintenance;
      if (sweep != null) {
        unawaited(() async {
          try {
            await sweep();
          } on Object catch (e) {
            debugPrint('[SyncSched] maintenance sweep failed: $e');
          }
        }());
      }
      for (final p in _pairs) {
        _trigger(p, reason: 'periodic rescan');
      }
    });
    // Cloud poll (§5.2): a cheap beacon check per lanCloud pair — the adapter
    // short-circuits on an unchanged fingerprint and self-gates on tier/mode.
    final pull = _cloudPull;
    if (pull != null) {
      _cloudPollTimer ??= Timer.periodic(cloudPollEvery, (_) {
        for (final p in _pairs) {
          if (!p.paused && p.mode == 'lanCloud') {
            _contained('cloud pull ${p.id}', () => pull(p));
          }
        }
      });
    }
  }

  void _contained(String what, Future<void> Function() run) {
    unawaited(() async {
      try {
        await run();
      } on Object catch (e) {
        debugPrint('[SyncSched] $what failed: $e');
      }
    }());
  }

  void _onPairs(List<SyncPair> pairs) {
    _pairs = pairs;
    final wanted = {for (final p in pairs.where((p) => !p.paused)) p.id: p};

    // Stop watchers for removed/paused pairs.
    for (final id in _watchers.keys.toList()) {
      if (!wanted.containsKey(id)) {
        _watcherSubs.remove(id)?.cancel();
        _watchers.remove(id)?.dispose();
      }
    }
    // Start watchers for new/resumed pairs.
    for (final p in wanted.values) {
      if (_watchers.containsKey(p.id)) continue;
      final w = _watcherFactory(_resolveRoot(p.rootPath));
      _watchers[p.id] = w;
      _watcherSubs[p.id] =
          w.changes.listen((_) => _trigger(p, reason: 'folder changed'));
      w.start();
    }
  }

  void _onDevices(List<DiscoveredDevice> devices) {
    final now = {for (final d in devices) d.fingerprint};
    final appeared = now.difference(_onlineFps);
    _onlineFps = now;
    if (appeared.isEmpty) return;
    // A peer coming online is the moment to flush everything queued for it.
    for (final p in _pairs) {
      if (!p.paused && appeared.contains(p.peerFingerprint)) {
        _trigger(p, reason: 'peer online');
      }
    }
  }

  void _trigger(SyncPair snapshot, {required String reason}) {
    // The watcher closure captured the pair row as it was when the watcher
    // started — resolve the LIVE row so a mode/pause change applies without
    // restarting the watcher.
    SyncPair pair = snapshot;
    for (final p in _pairs) {
      if (p.id == snapshot.id) {
        pair = p;
        break;
      }
    }
    if (pair.paused) return;
    DiscoveredDevice? peer;
    for (final d in _currentDevices()) {
      if (d.fingerprint == pair.peerFingerprint) {
        peer = d;
        break;
      }
    }
    if (peer == null) {
      // Peer away: hand the delta to the cloud (store-and-forward, §5.3) —
      // LAN always wins when available, the cloud only covers absence.
      final push = _cloudPush;
      if (push != null && pair.mode == 'lanCloud') {
        debugPrint('[SyncSched] ${pair.id}: $reason → cloud push (peer away)');
        _contained('cloud push ${pair.id}', () => push(pair));
      }
      return; // the peer-online trigger handles the LAN flush
    }
    final target = peer; // non-nullable copy (closure capture blocks promotion)
    debugPrint('[SyncSched] ${pair.id}: $reason → syncNow');
    // syncNow serializes per pair; errors already surface on the engine status
    // stream. try/catch (NOT Future.catchError) so a runner whose runtime
    // future carries a value type can't turn a failure into an unhandled
    // "handler must return a value of the future's type".
    unawaited(() async {
      try {
        await _run(pair, target);
      } on Object catch (e) {
        debugPrint('[SyncSched] ${pair.id}: sync failed: $e');
      }
    }());
  }

  Future<void> dispose() async {
    await _pairsSub?.cancel();
    await _deviceSub?.cancel();
    _rescanTimer?.cancel();
    _cloudPollTimer?.cancel();
    for (final s in _watcherSubs.values) {
      await s.cancel();
    }
    for (final w in _watchers.values) {
      await w.dispose();
    }
    _watcherSubs.clear();
    _watchers.clear();
  }
}
