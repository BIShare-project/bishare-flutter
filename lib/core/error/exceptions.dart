/// Data-layer exceptions. These are thrown by datasources and translated into
/// [Failure]s by repositories via `error_mapper.dart`.
library;

/// Thrown when the peer HTTP server returns a non-2xx status we recognise.
class TransferHttpException implements Exception {
  const TransferHttpException(this.statusCode, [this.body]);
  final int statusCode;
  final String? body;

  @override
  String toString() => 'TransferHttpException($statusCode): ${body ?? ''}';
}

/// Thrown when a SHA-256 verification fails on a received file.
class IntegrityException implements Exception {
  const IntegrityException(this.fileName);
  final String fileName;

  @override
  String toString() => 'IntegrityException: $fileName';
}

/// Thrown when E2E decryption of a chunk fails (bad key / tampered data).
class DecryptionException implements Exception {
  const DecryptionException([this.detail]);
  final String? detail;

  @override
  String toString() => 'DecryptionException: ${detail ?? ''}';
}

/// Thrown when the user cancels an in-flight transfer.
class CancelledException implements Exception {
  const CancelledException();
  @override
  String toString() => 'CancelledException';
}
