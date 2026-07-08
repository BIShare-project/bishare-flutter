import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/storage/app_database.dart';

/// Single source of truth for transfer history + the Inbox. Persists every
/// received file (by subscribing to [TransferServer.received]) and every sent
/// file, into the drift [AppDatabase]. Persistence happens regardless of whether
/// any screen is open.
class HistoryRepository {
  HistoryRepository(this._db);

  final AppDatabase _db;
  StreamSubscription<ReceivedFile>? _sub;

  /// Start persisting received files. Idempotent; call once at startup.
  void attach(TransferServer server) {
    _sub ??= server.received.listen(recordReceived);
  }

  Future<void> recordReceived(ReceivedFile f) => _db.insertRecord(
    TransferRecordsCompanion.insert(
      fileName: f.fileName,
      fileSize: f.size,
      direction: 'received',
      deviceAlias: f.senderAlias,
      timestamp: f.receivedAt,
      savedPath: Value(f.savedPath),
      fileType: Value(f.fileType),
      deviceFingerprint: Value(f.senderFingerprint),
      encrypted: Value(f.encrypted),
      verified: Value(f.verified),
    ),
  );

  Future<void> recordSent({
    required String fileName,
    required int size,
    required String deviceAlias,
    String? fileType,
    String? deviceFingerprint,
    bool encrypted = false,
  }) => _db.insertRecord(
    TransferRecordsCompanion.insert(
      fileName: fileName,
      fileSize: size,
      direction: 'sent',
      deviceAlias: deviceAlias,
      timestamp: DateTime.now(),
      fileType: Value(fileType),
      deviceFingerprint: Value(deviceFingerprint),
      encrypted: Value(encrypted),
    ),
  );

  /// Received files, newest first (the Inbox feed).
  Stream<List<TransferRecord>> watchReceived() => _db.watchReceived();

  /// Full transfer history (sent + received).
  Stream<List<TransferRecord>> watchAll() => _db.watchAll();

  Future<void> delete(int id) => _db.deleteRecord(id);
  Future<void> clear() => _db.clearHistory();

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
