import 'package:drift/drift.dart' show Value;

import '../../src/rust/api/scanner.dart';
import '../storage/app_database.dart';
import '../storage/sync_tables.dart';
import 'ignore_rules.dart';
import 'sync_models.dart';

/// The `scan_and_hash` FFI shape, injectable so [ManifestStore] is testable with
/// a canned scan stream (no native library). `stabilityMs` is `int` — the native
/// resolution of FRB's `PlatformInt64` (this feature ships on native only).
typedef ScanFn = Stream<ScanEvent> Function({
  required String root,
  required List<FfiPriorEntry> prior,
  required int batchSize,
  required int stabilityMs,
});

/// Outcome of a rescan: the fresh in-memory manifest (already ignore-filtered),
/// the scanner counters, and whether the persisted `SyncEntries` actually moved
/// (so the engine can skip a diff when nothing changed).
class ManifestScanResult {
  const ManifestScanResult({
    required this.entries,
    required this.changed,
    this.stats,
  });

  final List<ManifestEntry> entries;
  final bool changed;
  final FfiScanStats? stats;
}

/// Materializes and persists a pair's local manifest. It drives the Rust scanner
/// (which hashes only changed files), applies the pair's ignore rules, upserts
/// the survivors into `SyncEntries`, and — two-way (M2) — turns vanished paths
/// into `SyncTombstones` (an explicit local delete that can propagate) instead
/// of silently dropping rows. Rows whose content changed on disk are stamped
/// `originFp = ownFp`: "this device authored the current version", the signal
/// the conflict rules (§6.1) use to tell a local edit from a synced-in one.
class ManifestStore {
  ManifestStore(this._dao, {String ownFingerprint = '', ScanFn? scan})
      : _ownFp = ownFingerprint,
        _scan = scan ?? scanAndHash;

  final SyncDao _dao;
  final String _ownFp;
  final ScanFn _scan;

  /// Rescan [pair]'s root and reconcile `SyncEntries`. Unchanged files are never
  /// re-hashed (the scanner reuses the prior hash) and never re-written (we skip
  /// upserting identical rows, so a watch stream doesn't churn).
  Future<ManifestScanResult> rescan(SyncPair pair, {IgnoreRules? ignore}) async {
    final rules = ignore ?? IgnoreRules.defaults();
    final priorRows = await _dao.entriesFor(pair.id);

    final prior = <FfiPriorEntry>[
      for (final e in priorRows)
        if (!e.isDir && e.sha256 != null)
          FfiPriorEntry(
            path: e.path,
            size: BigInt.from(e.size),
            mtimeMs: e.mtimeMs,
            sha256: e.sha256!,
          ),
    ];

    final entries = <ManifestEntry>[];
    FfiScanStats? stats;
    await for (final ev in _scan(
      root: pair.rootPath,
      prior: prior,
      batchSize: 512,
      stabilityMs: 2000,
    )) {
      switch (ev) {
        case ScanEvent_Batch(:final field0):
          for (final e in field0) {
            if (rules.isIgnored(e.path, isDir: e.isDir)) continue;
            entries.add(ManifestEntry(
              path: e.path,
              size: e.size.toInt(),
              mtimeMs: e.mtimeMs,
              sha256: e.sha256,
              isDir: e.isDir,
            ));
          }
        case ScanEvent_Done(:final field0):
          stats = field0;
      }
    }

    final changed = await _reconcile(pair.id, entries, priorRows, stats);
    return ManifestScanResult(entries: entries, changed: changed, stats: stats);
  }

  /// Upsert new/changed rows and tombstone vanished ones. Returns whether the
  /// persisted manifest moved at all.
  ///
  /// * A row whose on-disk content CHANGED is stamped `originFp = ownFp` — this
  ///   device authored the current version (feeds the §6.1 conflict rules). An
  ///   unchanged row keeps its origin (a synced-in file stays peer-authored).
  /// * A vanished path becomes a `SyncTombstone` (originFp = ownFp): an explicit
  ///   local delete that the exchange propagates. Silent row-drops would make a
  ///   local delete indistinguishable from "never had it" (two-way M2, §6.3).
  Future<bool> _reconcile(
    String pairId,
    List<ManifestEntry> fresh,
    List<SyncEntry> prior,
    FfiScanStats? stats,
  ) async {
    final priorByPath = {for (final e in prior) e.path: e};
    final freshPaths = {for (final e in fresh) e.path};
    final now = DateTime.now().millisecondsSinceEpoch;

    final toUpsert = <SyncEntriesCompanion>[];
    for (final e in fresh) {
      final p = priorByPath[e.path];
      final unchanged = p != null &&
          p.size == e.size &&
          p.mtimeMs == e.mtimeMs &&
          p.sha256 == e.sha256 &&
          p.isDir == e.isDir;
      if (unchanged) continue;
      // Content moved vs the prior row → locally authored; a brand-new path is
      // local too. (Peer-applied writes upsert their row with the peer's fp
      // BEFORE the next rescan, and arrive content-identical here → unchanged.)
      final contentMoved = p == null || p.sha256 != e.sha256 || p.size != e.size;
      toUpsert.add(SyncEntriesCompanion.insert(
        pairId: pairId,
        path: e.path,
        size: e.size,
        mtimeMs: e.mtimeMs,
        sha256: Value(e.sha256),
        isDir: Value(e.isDir),
        originFp: Value(contentMoved ? _ownFp : p.originFp),
      ));
    }
    if (toUpsert.isNotEmpty) await _dao.upsertEntries(toUpsert);

    // An EMPTY scan of a previously-populated pair is trustworthy only when the
    // walk was clean: scanner errors (unreadable/unmounted root — the iOS
    // scoped-folder failure mode) with zero entries mean "couldn't look", and
    // tombstoning everything would propagate a catastrophic delete. Fail SAFE:
    // keep the rows, tombstone nothing (risk #9). A clean empty walk is a
    // genuine "user removed everything" and flows through as deletes.
    final walkFailed = stats == null || stats.errors > BigInt.zero;
    if (fresh.isEmpty && prior.isNotEmpty && walkFailed) return false;

    var deleted = 0;
    for (final p in prior) {
      if (!freshPaths.contains(p.path)) {
        await _dao.putTombstone(SyncTombstonesCompanion.insert(
          pairId: pairId,
          path: p.path,
          deletedAtMs: now,
          originFp: Value(_ownFp),
        ));
        await _dao.deleteEntry(pairId, p.path);
        deleted++;
      }
    }
    return toUpsert.isNotEmpty || deleted > 0;
  }

  /// The persisted manifest as [ManifestEntry]s — the input to `manifest_diff`
  /// against a peer/cloud manifest without forcing a fresh rescan.
  Future<List<ManifestEntry>> current(String pairId) async {
    final rows = await _dao.entriesFor(pairId);
    return [
      for (final e in rows)
        ManifestEntry(
          path: e.path,
          size: e.size,
          mtimeMs: e.mtimeMs,
          sha256: e.sha256,
          isDir: e.isDir,
        ),
    ];
  }
}
