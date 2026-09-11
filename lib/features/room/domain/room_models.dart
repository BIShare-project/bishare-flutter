import 'dart:convert';
import 'dart:typed_data';

/// A member of a transfer room. Remote rooms carry only fingerprint/alias/type;
/// LOCAL (Bonjour) rooms also carry the member's host+port so peers can reach
/// it directly for fan-out and file download.
class RoomMember {
  const RoomMember({
    required this.fingerprint,
    required this.alias,
    required this.deviceType,
    this.host = '',
    this.port = 0,
  });

  final String fingerprint;
  final String alias;
  final String deviceType;
  final String host;
  final int port;

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
    fingerprint: (j['fingerprint'] as String?) ?? '',
    alias: (j['alias'] as String?) ?? 'Device',
    deviceType: (j['deviceType'] as String?) ?? 'mobile',
    host: (j['host'] as String?) ?? '',
    port: (j['port'] as num?)?.toInt() ?? 0,
  );
}

/// The salt and sealed metadata of a file in an end-to-end encrypted room
/// (see `room_e2e.dart`).
class RoomFileEnc {
  const RoomFileEnc({required this.salt, required this.meta});
  final String salt;
  final String meta;
}

/// A file shared into a room. `thumbnail` is a base64 JPEG when present.
///
/// In an end-to-end encrypted room the server only knows a placeholder name
/// and the ciphertext size; [enc] carries the sealed metadata, and
/// [revealed] turns true once the room key has opened it into the real
/// name, type, size and preview.
class RoomFile {
  const RoomFile({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.size,
    required this.ownerFingerprint,
    required this.ownerAlias,
    this.thumbnail,
    this.enc,
    this.revealed = false,
  });

  final String id;
  final String fileName;
  final String fileType;
  final int size;
  final String ownerFingerprint;
  final String ownerAlias;
  final String? thumbnail;
  final RoomFileEnc? enc;
  final bool revealed;

  /// Encrypted, and the room key hasn't opened it (yet).
  bool get isSealed => enc != null && !revealed;

  factory RoomFile.fromJson(Map<String, dynamic> j) {
    final enc = j['enc'];
    return RoomFile(
      id: (j['id'] as String?) ?? '',
      fileName: (j['fileName'] as String?) ?? 'file',
      fileType: (j['fileType'] as String?) ?? 'application/octet-stream',
      size: (j['size'] as num?)?.toInt() ?? 0,
      ownerFingerprint: (j['ownerFingerprint'] as String?) ?? '',
      ownerAlias: (j['ownerAlias'] as String?) ?? 'Device',
      thumbnail: j['thumbnail'] as String?,
      enc: enc is Map && enc['salt'] is String && enc['meta'] is String
          ? RoomFileEnc(salt: enc['salt'] as String, meta: enc['meta'] as String)
          : null,
    );
  }

  /// This file with its sealed metadata opened.
  RoomFile reveal({
    required String name,
    required String type,
    required int plainSize,
    String? preview,
  }) => RoomFile(
    id: id,
    fileName: name,
    fileType: type,
    size: plainSize,
    ownerFingerprint: ownerFingerprint,
    ownerAlias: ownerAlias,
    thumbnail: preview,
    enc: enc,
    revealed: true,
  );

  /// Decoded thumbnail bytes, or null.
  Uint8List? get thumbnailBytes {
    final t = thumbnail;
    if (t == null || t.isEmpty) return null;
    try {
      return base64Decode(t);
    } on Object {
      return null;
    }
  }
}

/// Live room summary (from `/info` and the WS `sync` frame).
class RoomInfo {
  const RoomInfo({
    required this.code,
    required this.hostAlias,
    required this.hostFingerprint,
    required this.memberCount,
    required this.fileCount,
    this.uploadingAlias,
    this.uploadingFileName,
    this.e2eKid,
  });

  final String code;
  final String hostAlias;
  final String hostFingerprint;
  final int memberCount;
  final int fileCount;
  final String? uploadingAlias;
  final String? uploadingFileName;

  /// Key id of an end-to-end encrypted room; null for a plaintext room.
  final String? e2eKid;

  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
    code: (j['code'] as String?) ?? '',
    hostAlias: (j['hostAlias'] as String?) ?? '',
    hostFingerprint: (j['hostFingerprint'] as String?) ?? '',
    memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
    fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
    uploadingAlias: j['uploadingAlias'] as String?,
    uploadingFileName: j['uploadingFileName'] as String?,
    e2eKid: e2eKidOf(j['e2e']),
  );
}

/// The kid of a room's `e2e` field (`{v: 1, kid}`), or null.
String? e2eKidOf(Object? e2e) {
  if (e2e is! Map || e2e['v'] != 1) return null;
  final kid = e2e['kid'];
  return kid is String && kid.length == 22 ? kid : null;
}

/// Whether a Cloud room's files are end-to-end encrypted, as this device sees it.
enum RoomSecurity {
  /// Not a Cloud room, or not known yet.
  unknown,

  /// A room made by an older app: files are stored as sent.
  plain,

  /// Encrypted, but no member has handed this device the key yet.
  waitingForKey,

  /// Encrypted, and this device holds the key.
  encrypted,
}

/// The identity of a joined room + whether we host it.
class RoomSession {
  const RoomSession({
    required this.code,
    required this.hostFingerprint,
    required this.hostAlias,
    required this.isHost,
    this.hostToken,
    this.remote = true,
  });

  final String code;
  final String hostFingerprint;
  final String hostAlias;
  final bool isHost;

  /// Present only when we created the room (needed to close it).
  final String? hostToken;

  /// True for relay rooms (vs. local Bonjour rooms).
  final bool remote;
}
