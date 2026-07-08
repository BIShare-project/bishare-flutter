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

/// A file shared into a room. `thumbnail` is a base64 JPEG when present.
class RoomFile {
  const RoomFile({
    required this.id,
    required this.fileName,
    required this.fileType,
    required this.size,
    required this.ownerFingerprint,
    required this.ownerAlias,
    this.thumbnail,
  });

  final String id;
  final String fileName;
  final String fileType;
  final int size;
  final String ownerFingerprint;
  final String ownerAlias;
  final String? thumbnail;

  factory RoomFile.fromJson(Map<String, dynamic> j) => RoomFile(
    id: (j['id'] as String?) ?? '',
    fileName: (j['fileName'] as String?) ?? 'file',
    fileType: (j['fileType'] as String?) ?? 'application/octet-stream',
    size: (j['size'] as num?)?.toInt() ?? 0,
    ownerFingerprint: (j['ownerFingerprint'] as String?) ?? '',
    ownerAlias: (j['ownerAlias'] as String?) ?? 'Device',
    thumbnail: j['thumbnail'] as String?,
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
  });

  final String code;
  final String hostAlias;
  final String hostFingerprint;
  final int memberCount;
  final int fileCount;
  final String? uploadingAlias;
  final String? uploadingFileName;

  factory RoomInfo.fromJson(Map<String, dynamic> j) => RoomInfo(
    code: (j['code'] as String?) ?? '',
    hostAlias: (j['hostAlias'] as String?) ?? '',
    hostFingerprint: (j['hostFingerprint'] as String?) ?? '',
    memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
    fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
    uploadingAlias: j['uploadingAlias'] as String?,
    uploadingFileName: j['uploadingFileName'] as String?,
  );
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
