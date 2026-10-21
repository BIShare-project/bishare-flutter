import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// What one read of a file to upload found.
class VaultSnapshot {
  const VaultSnapshot({
    required this.hash,
    required this.size,
    required this.modifiedMs,
    required this.compressed,
  });

  /// SHA-256 of exactly the bytes read.
  final Uint8List hash;
  final int size;

  /// The file's modification time when it was read: the sealing step checks
  /// the file is still the one that was hashed.
  final int modifiedMs;

  /// A raw-DEFLATE copy was written next to it (VAULT-SPEC "Compression").
  final bool compressed;
}

/// The heavy file work of Drive uploads and downloads, each on its own
/// isolate so the screen never stops: hashing, compressing and inflating
/// files of up to tens of megabytes in memory, or more by streaming.
///
/// Raw DEFLATE (RFC 1951) from dart:io's zlib: the bytes differ from the Rust
/// core's, the content does not, and any raw-DEFLATE reader opens either.
abstract final class VaultFileWork {
  /// Read [path] once: its hash and size, and with [zPath] its compressed
  /// copy there when that is at least 10% smaller (written under a temporary
  /// name first, so a half-written copy is never mistaken for a whole one).
  static Future<VaultSnapshot> snapshot(String path, {String? zPath}) =>
      Isolate.run(() async {
        final file = File(path);
        final modified = (await file.lastModified()).millisecondsSinceEpoch;
        if (zPath == null) {
          var size = 0;
          final digest = await sha256
              .bind(
                file.openRead().map((chunk) {
                  size += chunk.length;
                  return chunk;
                }),
              )
              .first;
          return VaultSnapshot(
            hash: Uint8List.fromList(digest.bytes),
            size: size,
            modifiedMs: modified,
            compressed: false,
          );
        }
        final bytes = await file.readAsBytes();
        final hash = Uint8List.fromList(sha256.convert(bytes).bytes);
        final packed = ZLibEncoder(raw: true, level: 6).convert(bytes);
        var compressed = false;
        if (packed.length <= bytes.length * 0.9) {
          final tmp = File('$zPath.tmp');
          await tmp.writeAsBytes(packed, flush: true);
          await tmp.rename(zPath);
          compressed = true;
        }
        return VaultSnapshot(
          hash: hash,
          size: bytes.length,
          modifiedMs: modified,
          compressed: compressed,
        );
      });

  /// Inflate [input] (raw DEFLATE) into [output]: it must give exactly
  /// [size] bytes whose SHA-256 is [hash]. Stops as soon as it gives more,
  /// so a crafted stream cannot fill the disk.
  static Future<void> inflate(
    String input,
    String output,
    int size,
    Uint8List? hash,
  ) => Isolate.run(() async {
    final sink = File(output).openWrite();
    var n = 0;
    final digest = await sha256
        .bind(
          File(input).openRead().transform(ZLibDecoder(raw: true)).map((chunk) {
            n += chunk.length;
            if (n > size) {
              throw const FormatException('more bytes than the file has');
            }
            sink.add(chunk);
            return chunk;
          }),
        )
        .first
        .whenComplete(sink.close);
    _check(n, size, digest.bytes, hash);
  });

  /// [path] has exactly [size] bytes whose SHA-256 is [hash].
  static Future<void> verify(String path, int size, Uint8List? hash) =>
      Isolate.run(() async {
        var n = 0;
        final digest = await sha256
            .bind(
              File(path).openRead().map((chunk) {
                n += chunk.length;
                return chunk;
              }),
            )
            .first;
        _check(n, size, digest.bytes, hash);
      });

  static void _check(int n, int size, List<int> got, Uint8List? want) {
    if (n != size) {
      throw FormatException('the file has $n bytes, not $size');
    }
    if (want == null) return;
    if (got.length != want.length) {
      throw const FormatException('the content is not what was stored');
    }
    for (var i = 0; i < got.length; i++) {
      if (got[i] != want[i]) {
        throw const FormatException('the content is not what was stored');
      }
    }
  }
}
