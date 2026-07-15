import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/locator.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/storage/sync_tables.dart';
import '../../../core/sync/sync_roots.dart';
import '../../discovery/data/discovery_service.dart';
import '../../discovery/domain/discovered_device.dart';
import '../data/sync_engine.dart';

/// One pair row for the UI: the drift row + live engine phase + peer presence.
class SyncPairView extends Equatable {
  const SyncPairView({
    required this.pair,
    required this.displayRoot,
    required this.phase,
    required this.peerOnline,
    this.pushedFiles = 0,
    this.totalFiles = 0,
    this.conflicts = 0,
    this.errorMessage,
  });

  final SyncPair pair;

  /// The pair root as a real filesystem path (stored form may be portable).
  final String displayRoot;
  final SyncPhase phase;
  final bool peerOnline;
  final int pushedFiles;
  final int totalFiles;

  /// Unresolved conflicts recorded for this pair (badge + resolution sheet).
  final int conflicts;
  final String? errorMessage;

  @override
  List<Object?> get props => [
        pair,
        displayRoot,
        phase,
        peerOnline,
        pushedFiles,
        totalFiles,
        conflicts,
        errorMessage,
      ];
}

class FolderSyncState extends Equatable {
  const FolderSyncState({
    this.pairs = const [],
    this.loaded = false,
    this.busy = false,
    this.errorKey,
  });

  final List<SyncPairView> pairs;
  final bool loaded;

  /// A pairing invite is being sent (spinner on the setup flow).
  final bool busy;

  /// Localization key of a transient error (peer offline, invite failed…).
  final String? errorKey;

  FolderSyncState copyWith({
    List<SyncPairView>? pairs,
    bool? loaded,
    bool? busy,
    String? errorKey,
    bool clearError = false,
  }) => FolderSyncState(
    pairs: pairs ?? this.pairs,
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
    errorKey: clearError ? null : (errorKey ?? this.errorKey),
  );

  @override
  List<Object?> get props => [pairs, loaded, busy, errorKey];
}

/// Drives the Folder Sync screen: watches the pair list, folds in live engine
/// status + peer presence, and fronts the engine's pairing/sync calls.
class FolderSyncCubit extends Cubit<FolderSyncState> {
  FolderSyncCubit(this._engine, this._dao, this._discovery)
      : super(const FolderSyncState()) {
    _pairsSub = _dao.watchPairs().listen(_onPairs);
    _statusSub = _engine.status.listen(_onStatus);
    _discoverySub = _discovery.devices.listen((_) => _refold());
    _conflictsSub = _dao.watchAllUnresolvedConflicts().listen((rows) {
      final counts = <String, int>{};
      for (final r in rows) {
        counts[r.pairId] = (counts[r.pairId] ?? 0) + 1;
      }
      _conflictCounts
        ..clear()
        ..addAll(counts);
      _refold();
    });
  }

  final SyncEngine _engine;
  final SyncDao _dao;
  final DiscoveryService _discovery;

  late final StreamSubscription<List<SyncPair>> _pairsSub;
  late final StreamSubscription<SyncPairStatus> _statusSub;
  late final StreamSubscription<Object?> _discoverySub;
  late final StreamSubscription<List<SyncConflict>> _conflictsSub;
  final Map<String, int> _conflictCounts = {};

  List<SyncPair> _pairs = const [];
  final Map<String, SyncPairStatus> _live = {};

  void _onPairs(List<SyncPair> pairs) {
    _pairs = pairs;
    _refold();
  }

  void _onStatus(SyncPairStatus s) {
    _live[s.pairId] = s;
    _refold();
  }

  void _refold() {
    final online = {for (final d in _discovery.current) d.fingerprint};
    emit(state.copyWith(
      loaded: true,
      pairs: [
        for (final p in _pairs)
          SyncPairView(
            pair: p,
            displayRoot: getIt<SyncRootResolver>().resolve(p.rootPath),
            phase: _live[p.id]?.phase ?? SyncPhase.idle,
            peerOnline: online.contains(p.peerFingerprint),
            pushedFiles: _live[p.id]?.pushedFiles ?? 0,
            totalFiles: _live[p.id]?.totalFiles ?? 0,
            conflicts: _conflictCounts[p.id] ?? 0,
            errorMessage: _live[p.id]?.phase == SyncPhase.error
                ? _live[p.id]?.message
                : null,
          ),
      ],
    ));
  }

  /// Invite [peerFingerprint]'s device (must be online) to sync [rootPath].
  Future<PairInviteOutcome?> createPair({
    required String peerFingerprint,
    required String rootPath,
  }) async {
    final device = _onlineDevice(peerFingerprint);
    if (device == null) {
      emit(state.copyWith(errorKey: 'sync.error_peer_offline'));
      return null;
    }
    emit(state.copyWith(busy: true, clearError: true));
    try {
      final outcome = await _engine.invitePeer(
        host: device.host,
        port: device.port,
        rootPath: rootPath,
      );
      if (outcome == PairInviteOutcome.rejected) {
        emit(state.copyWith(busy: false, errorKey: 'sync.error_declined'));
      } else {
        emit(state.copyWith(busy: false));
      }
      return outcome;
    } on Object catch (e) {
      debugPrint('[FolderSync] invitePeer FAILED: $e');
      emit(state.copyWith(busy: false, errorKey: 'sync.error_invite_failed'));
      return null;
    }
  }

  /// Push this device's tree to the pair's peer (LAN, one-way M1).
  Future<void> syncNow(String pairId) async {
    final pair = _pairs.where((p) => p.id == pairId).firstOrNull;
    if (pair == null) return;
    final device = _onlineDevice(pair.peerFingerprint);
    if (device == null) {
      emit(state.copyWith(errorKey: 'sync.error_peer_offline'));
      return;
    }
    emit(state.copyWith(clearError: true));
    try {
      final report =
          await _engine.syncNow(pairId, host: device.host, port: device.port);
      if (report.scanned == 0) {
        // Never silently "up to date" on an empty/unreadable root — this is
        // exactly how an iOS scoped-folder miss looked before (0 files seen).
        emit(state.copyWith(errorKey: 'sync.warn_empty_scan'));
      }
    } on Object {
      // The engine already emitted SyncPhase.error with the message.
    }
  }

  Future<void> setPaused(String pairId, bool paused) =>
      _dao.setPaused(pairId, paused);

  /// Enable/disable the cloud fallback for a pair (Q1 Pro gating happens at
  /// the call site with the live tier; the adapter re-gates on every run).
  Future<void> setCloud(String pairId, bool enabled) =>
      _dao.setMode(pairId, enabled ? 'lanCloud' : 'lanOnly');

  Future<void> deletePair(String pairId) => _dao.deletePair(pairId);

  /// Unresolved conflicts for the resolution sheet (newest first).
  Future<List<SyncConflict>> conflictsFor(String pairId) =>
      _dao.unresolvedConflictsFor(pairId);

  /// Apply a resolution choice; the watch stream refreshes the badge.
  Future<void> resolveConflict(String conflictId, ConflictChoice choice) =>
      _engine.resolveConflict(conflictId, choice);

  void clearError() {
    if (state.errorKey != null) emit(state.copyWith(clearError: true));
  }

  DiscoveredDevice? _onlineDevice(String fingerprint) {
    for (final d in _discovery.current) {
      if (d.fingerprint == fingerprint) return d;
    }
    return null;
  }

  @override
  Future<void> close() async {
    await _pairsSub.cancel();
    await _statusSub.cancel();
    await _discoverySub.cancel();
    await _conflictsSub.cancel();
    return super.close();
  }
}
