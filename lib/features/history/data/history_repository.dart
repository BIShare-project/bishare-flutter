import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:mime/mime.dart';

import '../../../core/server/transfer_server.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/storage/android_downloads_channel.dart';
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
    _server = server;
    _sub ??= server.received.listen(recordReceived);
  }

  TransferServer? _server;

  Future<void> recordReceived(ReceivedFile f) async {
    // A file received over one already there ("Replace") takes its place in
    // the Inbox too, instead of two tiles for one file.
    await _db.deleteReceivedAt(f.savedPath);
    await _db.insertRecord(_receivedRow(f));
    // Android: received photos and videos show in the gallery in place, so
    // a received Live Photo picked from the Photos tab is still the file
    // recorded here (its pair is found by this path).
    final t = f.fileType ?? lookupMimeType(f.savedPath) ?? '';
    if (Platform.isAndroid &&
        (t.startsWith('image/') || t.startsWith('video/'))) {
      _queueScan(f.savedPath);
    }
  }

  // Indexed once the transfer has ended: every MediaStore insert makes the
  // gallery and the Photos tab reload, and 100 photos arrive in seconds.
  final _toScan = <String>[];
  Timer? _scanTimer;

  void _queueScan(String path) {
    _toScan.add(path);
    _scanTimer?.cancel();
    _scanTimer = Timer(const Duration(milliseconds: 1500), _flushScan);
  }

  void _flushScan() {
    if (_toScan.isEmpty) return;
    if (_server?.isReceiving ?? false) {
      _scanTimer = Timer(const Duration(milliseconds: 1500), _flushScan);
      return;
    }
    final paths = [..._toScan];
    _toScan.clear();
    unawaited(AndroidDownloadsPath.scanMedia(paths));
  }

  TransferRecordsCompanion _receivedRow(ReceivedFile f) =>
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
        liveGroup: Value(f.liveGroup),
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

  /// The file of the other half of the received Live Photo at [path], when
  /// it is still on disk.
  Future<String?> livePartnerPath(String path) async {
    final other = (await _db.receivedLivePartner(path))?.savedPath;
    return other != null && File(other).existsSync() ? other : null;
  }

  Future<void> clear() => _db.clearHistory();

  Future<void> dispose() async {
    _scanTimer?.cancel();
    _server = null;
    _flushScan();
    await _sub?.cancel();
    _sub = null;
  }
}
