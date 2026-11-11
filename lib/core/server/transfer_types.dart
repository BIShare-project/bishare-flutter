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
    this.syncPairId,
    this.syncRootPath,
  });

  final String sessionId;
  final DeviceInfo sender;
  final Map<String, FileMetadata> files;
  final Map<String, String> tokens; // fileId -> upload token
  final DateTime createdAt;

  /// Derived AES-256 key for E2E (32 bytes), or null for a plaintext session.
  final List<int>? symmetricKey;

  /// Folder-sync payload session (Tahap 4): each file routes to [syncRootPath]
  /// at its `FileMetadata.relPath` (mirror semantics — exact name, overwrite,
  /// no inbox record). Set only when the prepare carried a `syncPairId` that
  /// resolved to a configured pair for the sender's fingerprint.
  final String? syncPairId;
  final String? syncRootPath;

  bool get isSync => syncRootPath != null;

  bool get encrypted => symmetricKey != null;

  DateTime lastActivity = DateTime.now();
  final Set<String> completedFileIds = {};

  /// Live byte counters of QUIC files currently in flight (fileId → received).
  /// Phase 2b senders stream several files CONCURRENTLY over one connection, so
  /// session progress is completed-bytes + the SUM of these, not a single
  /// "current file" counter.
  final Map<String, int> quicInFlight = {};

  /// The same for TCP files in flight (a sender uploads several at once).
  final Map<String, int> tcpInFlight = {};

  /// Upload requests whose body is being read right now.
  int activeUploads = 0;

  bool get isComplete => completedFileIds.length >= files.length;

  /// The sender can continue a cut-off TCP upload from where it stopped
  /// (`PrepareRequest.tcpResume`).
  bool tcpResume = false;

  /// The sender cancelled: nothing is kept for a resume.
  bool cancelled = false;

  /// Files whose TCP upload was cut off: what arrived so far (fileId →).
  final Map<String, PartialUpload> partials = {};

  /// A file with the name of one already there replaces it ([NameClash]).
  bool replaceExisting = false;

  /// Paths (lower case) this session saved to: a second file of the same name
  /// in one transfer never replaces the first.
  final Set<String> savedPaths = {};
}

/// The start of a file whose upload was cut off, kept so the sender can send
/// only the rest. [bytes] is plaintext, already decrypted.
class PartialUpload {
  const PartialUpload(this.path, this.bytes);

  final String path;
  final int bytes;
}

/// What an interrupted transfer left behind for its sender: the files that
/// arrived whole and the ones cut off, keyed by [resumeKey], so the next
/// offer from the same sender skips the first and continues the second.
class ResumeLeftover {
  ResumeLeftover(this.at);

  DateTime at;
  final Set<String> done = {};
  final Map<String, PartialUpload> partials = {};
}

/// Identifies "the same file" across two offers from one sender.
String resumeKey(FileMetadata f) =>
    '${f.fileName}|${f.size}|${f.mtimeMs ?? ''}|${f.sha256 ?? ''}';

/// An incoming transfer awaiting the user's accept/reject decision. The prepare
/// HTTP handler blocks on [decision] until the UI resolves it (or it times out).
class PendingTransfer {
  PendingTransfer({
    required this.session,
    this.keyChanged = false,
    this.clashes = 0,
  });

  final TransferSession session;

  /// Files whose name is already taken in the save folder, counted only when
  /// the setting is [NameClash.ask]: the prompt then asks what to do.
  final int clashes;

  /// The answer to [clashes]: replace the files already there.
  set replaceExisting(bool on) => session.replaceExisting = on;
  bool get replaceExisting => session.replaceExisting;

  /// P0.5: the sender's X25519 key differs from the one we pinned for its
  /// fingerprint (device replaced, or a possible impersonator). The accept
  /// prompt surfaces this so the user can decide deliberately.
  final bool keyChanged;

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
    this.transport = 'TCP',
  });

  final String sessionId;
  final String senderAlias;
  final int totalFiles;
  final int completedFiles;
  final String currentFileName;
  final int bytesReceived;
  final int totalBytes;
  final bool isComplete;

  /// Which transport is delivering this session ('TCP' | 'QUIC') — drives the
  /// receiver card's transport badge, mirroring the sender's live badge.
  final String transport;

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
    this.liveGroup,
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

  /// Half of a Live Photo ([FileMetadata.liveGroup]).
  final String? liveGroup;
}

/// Auto-accept policy (mirrors native `AutoAcceptMode`).
enum AutoAcceptMode { alwaysAsk, acceptAll, favoritesOnly }

/// What a received file does when its name is already taken in the save
/// folder: keep both (the new one becomes `IMG_4821 (1).HEIC`), replace the
/// old one, or ask in the accept prompt (keep both when accepted without a
/// prompt).
enum NameClash { keepBoth, replace, ask }
