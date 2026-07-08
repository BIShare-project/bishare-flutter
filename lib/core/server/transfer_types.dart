import 'dart:async';

import '../protocol/device_info.dart';
import '../protocol/file_metadata.dart';
import '../protocol/file_request.dart';

/// Server-side state for one accepted transfer.
class TransferSession {
  TransferSession({
    required this.sessionId,
    required this.sender,
    required this.files,
    required this.tokens,
    required this.createdAt,
    this.symmetricKey,
  });

  final String sessionId;
  final DeviceInfo sender;
  final Map<String, FileMetadata> files;
  final Map<String, String> tokens; // fileId -> upload token
  final DateTime createdAt;

  /// Derived AES-256 key for E2E (32 bytes), or null for a plaintext session.
  final List<int>? symmetricKey;

  bool get encrypted => symmetricKey != null;

  DateTime lastActivity = DateTime.now();
  final Set<String> completedFileIds = {};

  bool get isComplete => completedFileIds.length >= files.length;
}

/// An incoming transfer awaiting the user's accept/reject decision. The prepare
/// HTTP handler blocks on [decision] until the UI resolves it (or it times out).
class PendingTransfer {
  PendingTransfer({required this.session});

  final TransferSession session;
  final Completer<bool> decision = Completer<bool>();

  String get id => session.sessionId;
  DeviceInfo get sender => session.sender;
  Map<String, FileMetadata> get files => session.files;

  int get totalBytes => files.values.fold<int>(0, (sum, f) => sum + f.size);

  void accept() {
    if (!decision.isCompleted) decision.complete(true);
  }

  void reject() {
    if (!decision.isCompleted) decision.complete(false);
  }
}

/// An incoming file-request (reverse flow) awaiting the user's decision. The
/// `/api/v1/request` handler blocks on [decision] until the UI resolves it or it
/// auto-declines after 60s. On accept, the responder sends files back to the
/// requester via the normal transfer path.
class PendingFileRequest {
  PendingFileRequest({required this.request});

  final FileRequestMessage request;
  final Completer<bool> decision = Completer<bool>();

  String get id => request.requestId;
  String get requesterAlias => request.requesterAlias;

  void respond(bool accepted) {
    if (!decision.isCompleted) decision.complete(accepted);
  }
}

/// Live receive progress for the UI.
class ReceiveProgress {
  const ReceiveProgress({
    required this.sessionId,
    required this.senderAlias,
    required this.totalFiles,
    required this.completedFiles,
    required this.currentFileName,
    required this.bytesReceived,
    required this.totalBytes,
    this.isComplete = false,
  });

  final String sessionId;
  final String senderAlias;
  final int totalFiles;
  final int completedFiles;
  final String currentFileName;
  final int bytesReceived;
  final int totalBytes;
  final bool isComplete;

  double get fraction => totalBytes == 0 ? 0 : bytesReceived / totalBytes;
}

/// A file that has been fully received and saved to disk.
class ReceivedFile {
  const ReceivedFile({
    required this.fileName,
    required this.savedPath,
    required this.size,
    required this.senderAlias,
    required this.receivedAt,
    required this.verified,
    this.fileType,
    this.senderFingerprint,
    this.encrypted = false,
  });

  final String fileName;
  final String savedPath;
  final int size;
  final String senderAlias;
  final DateTime receivedAt;
  final bool verified;
  final String? fileType;
  final String? senderFingerprint;
  final bool encrypted;
}

/// Auto-accept policy (mirrors native `AutoAcceptMode`).
enum AutoAcceptMode { alwaysAsk, acceptAll, favoritesOnly }
