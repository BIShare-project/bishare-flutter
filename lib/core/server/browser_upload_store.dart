import 'dart:async';
import 'dart:io';

/// Chunked, resumable browser uploads (`POST /api/v1/browser-upload-chunk`).
///
/// Design (feature #11): the browser slices a file into sequential chunks and
/// POSTs each with `X-Upload-Id` + `X-Chunk-Offset`; chunks are appended to a
/// `.browser-<id>.part` file in the incoming (save) directory. **The `.part`
/// length is the single source of truth for the resume offset** — there is no
/// database row, so a resume works even across an app restart (the browser
/// asks `GET /api/v1/browser-upload-status?id=` and continues from whatever
/// actually reached disk). The in-memory [_meta] map only caches display
/// metadata (name/size/mime); losing it is harmless because the browser
/// re-sends those headers with every chunk.
///
/// Kept separate from `TransferServer` (like `ClipboardTokenStore`) because
/// the server itself has no test harness — the 409 offset contract and the
/// cap/rollback behavior are unit-tested against this class directly.
class BrowserUploadStore {
  BrowserUploadStore(this._dir);

  /// The incoming directory (the receiver's save dir — evaluated per call
  /// because the user can change the save location while the server runs).
  final Directory Function() _dir;

  /// Per-upload size cap in bytes; 0 = unlimited. Mirrors the
  /// "Max upload size" setting.
  int maxBytes = 0;

  /// Max number of concurrent staging `.part` files before a **new** upload is
  /// refused (0 = unlimited). In-flight uploads always run to completion; only
  /// a brand-new id is turned away once we are at the cap, so a burst of
  /// abandoned parts cannot grow without bound between reaper passes.
  int maxStagingFiles = defaultMaxStagingFiles;

  /// Total staging bytes across all `.part` files before a **new** upload is
  /// refused (0 = unlimited). Off by default — a single legitimate large upload
  /// must not be blocked; the file-count cap is the primary bound.
  int maxStagingBytes = 0;

  /// The shipped, non-zero default for [maxStagingFiles]. 64 concurrent browser
  /// uploads is far past any real LAN-share use while still bounding disk use.
  static const int defaultMaxStagingFiles = 64;

  /// How long a finalized upload id stays replayable so a retried final chunk
  /// (whose success response was lost in transit) is answered idempotently
  /// instead of re-uploading — and saving a duplicate. See [rememberCompleted].
  static const Duration completedGrace = Duration(minutes: 10);

  final Map<String, BrowserUploadMeta> _meta = {};

  /// Per-id append serialization: each new append chains after the previous one
  /// for the same id so only one write touches a given `.part` at a time (the
  /// offset check + write is otherwise a TOCTOU race under concurrent chunks).
  final Map<String, Future<void>> _chains = {};

  /// Recently finalized upload ids → the saved file name, kept for
  /// [completedGrace] so a retried final chunk replays the original success.
  final Map<String, _CompletedUpload> _completed = {};

  /// Upload ids are browser-generated UUIDs; anything else (path characters,
  /// overlong strings) is rejected before it can touch a file name.
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9-]{8,64}$');

  static bool isValidId(String id) => _idPattern.hasMatch(id);

  /// The `.part` staging file for [id]. Hidden (dot-prefixed) so it never
  /// shows up in browser listings or folder zips.
  File partFile(String id) =>
      File('${_dir().path}${Platform.pathSeparator}.browser-$id.part');

  /// The verified resume offset — what actually reached disk.
  int offsetOf(String id) {
    final f = partFile(id);
    return f.existsSync() ? f.lengthSync() : 0;
  }

  /// Caches metadata carried on a chunk's headers (merging with what earlier
  /// chunks already declared).
  void remember(String id, {String? fileName, int? declaredSize, String? mime}) {
    final current = _meta[id];
    _meta[id] = BrowserUploadMeta(
      fileName: fileName ?? current?.fileName,
      declaredSize: declaredSize ?? current?.declaredSize,
      mime: mime ?? current?.mime,
    );
  }

  BrowserUploadMeta? metaOf(String id) => _meta[id];

  /// Appends [body] at [offset]. The offset MUST equal the current `.part`
  /// length; otherwise [BrowserAppendStatus.mismatch] is returned with the
  /// expected offset (→ HTTP 409, the browser realigns). On any write failure
  /// the file is truncated back to the pre-append length, so the next status
  /// probe never reports a half-written chunk as durable.
  ///
  /// Appends for the same [id] are serialized (chained through [_chains]) so two
  /// concurrent chunks — a browser retry racing the original, say — cannot both
  /// pass the offset check and interleave their writes; the offset is
  /// re-verified against the on-disk length inside that critical section and an
  /// overlap loses cleanly with [BrowserAppendStatus.mismatch].
  Future<BrowserAppendResult> append(
    String id,
    int offset,
    Stream<List<int>> body,
  ) =>
      _locked(id, () => _appendLocked(id, offset, body));

  Future<BrowserAppendResult> _appendLocked(
    String id,
    int offset,
    Stream<List<int>> body,
  ) async {
    final file = partFile(id);
    final isNew = !file.existsSync();
    final expected = isNew ? 0 : file.lengthSync();
    if (offset != expected) {
      return BrowserAppendResult(BrowserAppendStatus.mismatch, expected);
    }
    // Only brand-new uploads are subject to the staging cap; an upload already
    // on disk always finishes so a resume is never refused.
    if (isNew && _stagingAtCapacity()) {
      return const BrowserAppendResult(BrowserAppendStatus.capacity, 0);
    }
    final dir = _dir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final raf = await file.open(mode: FileMode.writeOnlyAppend);
    var written = 0;
    try {
      await for (final chunk in body) {
        if (maxBytes > 0 && expected + written + chunk.length > maxBytes) {
          await raf.truncate(expected);
          return BrowserAppendResult(BrowserAppendStatus.tooLarge, expected);
        }
        await raf.writeFrom(chunk);
        written += chunk.length;
      }
    } on Object {
      try {
        await raf.truncate(expected);
      } on Object {
        // Best effort — a failed rollback surfaces as a 409 on the retry.
      }
      return BrowserAppendResult(BrowserAppendStatus.failed, expected);
    } finally {
      await raf.close();
    }
    return BrowserAppendResult(BrowserAppendStatus.ok, expected + written);
  }

  /// Runs [action] after any append already queued for [id] has finished, and
  /// blocks the next one until this completes — a lightweight per-id mutex. A
  /// prior holder's failure is isolated (it never poisons the queued action).
  Future<T> _locked<T>(String id, Future<T> Function() action) {
    final prev = _chains[id];
    final completer = Completer<void>();
    _chains[id] = completer.future;
    Future<T> run() async {
      if (prev != null) {
        try {
          await prev;
        } on Object {
          // The previous holder's error belongs to its own caller.
        }
      }
      try {
        return await action();
      } finally {
        if (identical(_chains[id], completer.future)) _chains.remove(id);
        completer.complete();
      }
    }

    return run();
  }

  /// True when accepting a brand-new upload would breach the staging caps.
  bool _stagingAtCapacity() {
    if (maxStagingFiles <= 0 && maxStagingBytes <= 0) return false;
    final usage = _stagingUsage();
    if (maxStagingFiles > 0 && usage.count >= maxStagingFiles) return true;
    if (maxStagingBytes > 0 && usage.bytes >= maxStagingBytes) return true;
    return false;
  }

  /// Current count + total byte size of `.browser-*.part` staging files.
  ({int count, int bytes}) _stagingUsage() {
    final dir = _dir();
    if (!dir.existsSync()) return (count: 0, bytes: 0);
    var count = 0;
    var bytes = 0;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('.browser-') || !name.endsWith('.part')) continue;
      count++;
      try {
        bytes += entity.lengthSync();
      } on Object {
        // A file that vanished between listing and stat contributes nothing.
      }
    }
    return (count: count, bytes: bytes);
  }

  /// Records that [id] finalized as [savedFileName] so a retried final chunk
  /// (its success response lost in transit) replays the original success for
  /// [completedGrace] instead of re-uploading the whole file. Evicts entries
  /// that aged out of the grace window on the way in.
  void rememberCompleted(String id, String savedFileName, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _completed.removeWhere((_, e) => at.difference(e.at) > completedGrace);
    _completed[id] = _CompletedUpload(savedFileName, at);
  }

  /// The saved file name if [id] finalized within [completedGrace], else null
  /// (a genuinely new upload that happens to reuse an aged-out id is not
  /// shadowed). Evicts [id] once it has aged out.
  String? completedName(String id, {DateTime? now}) {
    final entry = _completed[id];
    if (entry == null) return null;
    final at = now ?? DateTime.now();
    if (at.difference(entry.at) > completedGrace) {
      _completed.remove(id);
      return null;
    }
    return entry.name;
  }

  /// Drops completed-id records that aged out of the grace window (called by
  /// the periodic reaper so the map cannot linger unbounded).
  void sweepCompleted({DateTime? now}) {
    final at = now ?? DateTime.now();
    _completed.removeWhere((_, e) => at.difference(e.at) > completedGrace);
  }

  /// Drops the staged `.part` and metadata (cap exceeded / size mismatch).
  void discard(String id) {
    _meta.remove(id);
    final f = partFile(id);
    if (f.existsSync()) f.deleteSync();
  }

  /// Forgets the metadata after the caller renamed the finished `.part` into
  /// its final place.
  void forget(String id) => _meta.remove(id);

  /// Deletes abandoned `.browser-*.part` staging files older than [maxAge]
  /// (a browser that never came back to resume). Runs at server start and again
  /// on a periodic reaper, so orphans no longer linger until the next launch.
  void pruneStale({Duration maxAge = const Duration(hours: 24)}) {
    final dir = _dir();
    if (!dir.existsSync()) return;
    final cutoff = DateTime.now().subtract(maxAge);
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('.browser-') || !name.endsWith('.part')) continue;
      try {
        if (entity.statSync().modified.isBefore(cutoff)) entity.deleteSync();
      } on Object {
        // Ignore — the reaper retries at the next start.
      }
    }
  }
}

/// Cached upload metadata (display only — never trusted for offsets).
class BrowserUploadMeta {
  const BrowserUploadMeta({this.fileName, this.declaredSize, this.mime});

  final String? fileName;
  final int? declaredSize;
  final String? mime;
}

enum BrowserAppendStatus { ok, mismatch, tooLarge, failed, capacity }

/// A recently finalized upload, kept for [BrowserUploadStore.completedGrace] so
/// a retried final chunk replays the original success instead of re-uploading.
class _CompletedUpload {
  const _CompletedUpload(this.name, this.at);

  final String name;
  final DateTime at;
}

class BrowserAppendResult {
  const BrowserAppendResult(this.status, this.offset);

  final BrowserAppendStatus status;

  /// For [BrowserAppendStatus.ok] the new end-of-file offset; for every other
  /// status the offset the browser should resume from.
  final int offset;
}
