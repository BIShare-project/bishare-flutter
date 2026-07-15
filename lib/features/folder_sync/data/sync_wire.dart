/// Wire layer for `POST /api/v1/sync` (Tahap 4 §5.1). One request = one
/// AEAD-encrypted manifest frame; one response = one AEAD-encrypted JSON ack.
///
/// Framing keeps the shipped protocol codecs in the loop: the manifest crosses
/// as a real `ManifestDelta` (0x0E) frame — encoded/decoded by the SAME Rust
/// structs every platform uses — inside the encrypted envelope. M1 always sends
/// a FULL snapshot (`baseCursor == 0`, ops = one `add` per live entry): the
/// receiver diffs it against its own local manifest with `manifest_diff`, so
/// correctness never depends on cursor continuity. Cursor deltas (baseCursor >
/// 0) are the M2 optimization; `newCursor` already carries the sender's cursor
/// so peers track each other from day one.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../../core/sync/sync_models.dart';
import '../../../src/rust/api/manifest.dart' as ffi;

/// The sender's manifest snapshot/delta as it crosses the wire.
class SyncManifestMessage {
  const SyncManifestMessage({
    required this.pairId,
    required this.baseCursor,
    required this.newCursor,
    required this.ops,
  });

  /// `BinaryManifestDelta.syncId` carries the pair id.
  final String pairId;

  /// 0 = full snapshot (ops rebuild the whole tree from empty).
  final int baseCursor;

  /// The sender's own cursor after this snapshot.
  final int newCursor;
  final List<DeltaOp> ops;

  bool get isFullSnapshot => baseCursor == 0;

  Map<String, dynamic> toJson() => {
    'syncId': pairId,
    'baseCursor': baseCursor,
    'newCursor': newCursor,
    'ops': ops.map((o) => o.toJson()).toList(),
  };

  factory SyncManifestMessage.fromJson(Map<String, dynamic> j) =>
      SyncManifestMessage(
        pairId: j['syncId'] as String,
        baseCursor: (j['baseCursor'] as num?)?.toInt() ?? 0,
        newCursor: (j['newCursor'] as num?)?.toInt() ?? 0,
        ops: ((j['ops'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DeltaOp.fromJson)
            .toList(growable: false),
      );
}

/// One file the receiver still needs the bytes for (an add/modify it could not
/// satisfy locally). The sender pushes these as a sync payload transfer.
class SyncNeededFile {
  const SyncNeededFile({required this.path, this.sha256, this.size});

  final String path;
  final String? sha256;
  final int? size;

  Map<String, dynamic> toJson() => {
    'path': path,
    if (sha256 != null) 'sha256': sha256,
    if (size != null) 'size': size,
  };

  factory SyncNeededFile.fromJson(Map<String, dynamic> j) => SyncNeededFile(
    path: j['path'] as String,
    sha256: j['sha256'] as String?,
    size: (j['size'] as num?)?.toInt(),
  );
}

/// The receiver's reply to a manifest: what it applied locally, what bytes it
/// still needs, and its record of the sender's cursor.
class SyncAckMessage {
  const SyncAckMessage({
    required this.pairId,
    required this.applied,
    required this.needed,
    required this.cursor,
  });

  final String pairId;

  /// Metadata-only ops applied (mkdir/rename/trash) in this exchange.
  final int applied;
  final List<SyncNeededFile> needed;

  /// The sender cursor the receiver has now recorded (== newCursor on success).
  final int cursor;

  Map<String, dynamic> toJson() => {
    'type': 'syncAck',
    'pairId': pairId,
    'applied': applied,
    'cursor': cursor,
    'needed': needed.map((n) => n.toJson()).toList(),
  };

  factory SyncAckMessage.fromJson(Map<String, dynamic> j) => SyncAckMessage(
    pairId: j['pairId'] as String,
    applied: (j['applied'] as num?)?.toInt() ?? 0,
    cursor: (j['cursor'] as num?)?.toInt() ?? 0,
    needed: ((j['needed'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SyncNeededFile.fromJson)
        .toList(growable: false),
  );
}

/// Encodes/decodes the manifest frame. Production uses the Rust protocol codec
/// (0x0E `ManifestDelta` — byte-identical to every other implementation);
/// tests inject [ManifestFrameCodec.json] to run without a native library.
class ManifestFrameCodec {
  const ManifestFrameCodec._(this._encode, this._decode);

  /// The shipped protocol frame (FFI). Default in production.
  factory ManifestFrameCodec.ffi() => ManifestFrameCodec._(
    (m) async => Uint8List.fromList(
      await ffi.encodeManifestDelta(deltaJson: jsonEncode(m.toJson())),
    ),
    (bytes) async {
      final decoded =
          jsonDecode(await ffi.decodeManifestFrame(bytes: bytes))
              as Map<String, dynamic>;
      if (decoded['type'] != 'manifestDelta') {
        throw FormatException('unexpected sync frame: ${decoded['type']}');
      }
      return SyncManifestMessage.fromJson(
        decoded['payload'] as Map<String, dynamic>,
      );
    },
  );

  /// A plain-JSON stand-in with the same shape — for unit tests only.
  factory ManifestFrameCodec.json() => ManifestFrameCodec._(
    (m) async => Uint8List.fromList(utf8.encode(jsonEncode(m.toJson()))),
    (bytes) async => SyncManifestMessage.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    ),
  );

  final Future<Uint8List> Function(SyncManifestMessage) _encode;
  final Future<SyncManifestMessage> Function(Uint8List) _decode;

  Future<Uint8List> encode(SyncManifestMessage m) => _encode(m);
  Future<SyncManifestMessage> decode(Uint8List bytes) => _decode(bytes);
}
