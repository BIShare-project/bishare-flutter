import 'dart:io';

/// Unix milliseconds for 3000-01-01 — anything at or past this is treated as
/// garbage (a sender sending seconds-as-millis would land in 1970, not here;
/// this guards the opposite mistake, nanoseconds or a corrupt header).
const int _maxMtimeMs = 32503680000000;

/// Whether [mtimeMs] is a value worth stamping on a received file. Zero is
/// "unknown", not 1970: every sender in the chain (browser JS, Kotlin, Swift,
/// Dart) reports a missing time as 0 or omits it, and a file stamped with the
/// epoch would read as a bug, not as fidelity.
bool isUsableMtime(int? mtimeMs) =>
    mtimeMs != null && mtimeMs > 0 && mtimeMs < _maxMtimeMs;

/// Stamp [file] with the sender's modification time so "Date modified" on the
/// receiver matches the original instead of the moment the transfer finished.
///
/// Best effort on purpose: call it AFTER the file has been closed and moved to
/// its final path (a later rename keeps the timestamp; a later write would
/// bump it again), and treat a failure as cosmetic — some filesystems and
/// Android's scoped-storage views refuse `utimes`, and the bytes are already
/// safely on disk by then.
Future<void> applyReceivedMtime(File file, int? mtimeMs) async {
  if (!isUsableMtime(mtimeMs)) return;
  try {
    await file.setLastModified(
      DateTime.fromMillisecondsSinceEpoch(mtimeMs!, isUtc: true),
    );
  } on FileSystemException {
    // Cosmetic: keep the file, lose the timestamp.
  }
}

/// The sender-side counterpart: a file's modification time as Unix
/// milliseconds, or null when the filesystem cannot say (e.g. a content URI
/// snapshot that never had one).
int? mtimeOf(File file) {
  try {
    final ms = file.lastModifiedSync().millisecondsSinceEpoch;
    return isUsableMtime(ms) ? ms : null;
  } on FileSystemException {
    return null;
  }
}
