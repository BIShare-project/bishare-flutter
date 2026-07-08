import 'dart:convert';
import 'dart:typed_data';

import 'package:bishare/core/constants/protocol.dart';
import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Validates the interop-critical E2E streaming framing that TransferClient
/// (sender) and TransferServer (receiver) implement, against the native spec:
///
///   header:  X-Encrypted: chunked
///   body:    repeat [ uint32 BE length ][ nonce(12) | ciphertext | tag(16) ]
///   chunk:   AES-256-GCM of a ≤256 KB plaintext slice, chunkIndex from 0
///   nonce:   baseNonce XOR bigEndian(chunkIndex) in the last 8 bytes
///   base:    NOT transmitted — recovered from chunk 0's embedded nonce
///
/// Crypto here uses the pure-Dart engine, which the interop tests already prove
/// is byte-identical to the native/Rust scheme; the production path uses the
/// same scheme via Rust FFI.
void main() {
  const chunkSize = BIShareConfig.defaultChunkSize;

  /// Sender: encrypt [plain] into the framed wire body.
  Future<Uint8List> frameBody(SessionCipher cipher, Uint8List plain) async {
    final baseNonce = SessionCipher.generateBaseNonce();
    final out = BytesBuilder();
    var index = 0;
    for (var off = 0; off < plain.length; off += chunkSize) {
      final end = (off + chunkSize < plain.length) ? off + chunkSize : plain.length;
      final enc = await cipher.encryptChunk(plain.sublist(off, end), index, baseNonce);
      final len = enc.length;
      out.add([
        (len >> 24) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 8) & 0xFF,
        len & 0xFF,
      ]);
      out.add(enc);
      index++;
    }
    return out.toBytes();
  }

  /// Receiver: parse [wire] delivered in [readSize] network reads and decrypt.
  Future<Uint8List> parseBody(
    SessionCipher cipher,
    Uint8List wire,
    int readSize,
  ) async {
    final plain = BytesBuilder();
    var buf = <int>[];
    var index = 0;
    Uint8List? baseNonce;
    for (var pos = 0; pos < wire.length; pos += readSize) {
      final end = (pos + readSize < wire.length) ? pos + readSize : wire.length;
      buf.addAll(wire.sublist(pos, end));
      var offset = 0;
      while (buf.length - offset >= 4) {
        final len = (buf[offset] << 24) |
            (buf[offset + 1] << 16) |
            (buf[offset + 2] << 8) |
            buf[offset + 3];
        if (buf.length - offset - 4 < len) break;
        final enc = Uint8List.fromList(buf.sublist(offset + 4, offset + 4 + len));
        final bn = baseNonce ??=
            Uint8List.fromList(enc.sublist(0, BIShareCrypto.gcmNonceSize));
        plain.add(await cipher.decryptChunk(enc, index, bn));
        offset += 4 + len;
        index++;
      }
      if (offset > 0) buf = buf.sublist(offset);
    }
    expect(buf, isEmpty, reason: 'no partial frame should remain');
    return plain.toBytes();
  }

  Future<(SessionCipher tx, SessionCipher rx)> pair() async {
    final (alice, _) = await E2ECrypto.create();
    final (bob, _) = await E2ECrypto.create();
    final tx = await alice.deriveSession(bob.publicKeyBase64);
    final rx = await bob.deriveSession(alice.publicKeyBase64);
    return (tx!, rx!);
  }

  test('multi-chunk payload round-trips (frame → parse) with sha256 intact', () async {
    final (tx, rx) = await pair();
    // 600 KB → spans 3 chunks (256 + 256 + 88 KB).
    final plain = Uint8List.fromList(
      List<int>.generate(600 * 1024, (i) => (i * 31 + 7) & 0xFF),
    );
    final wire = await frameBody(tx, plain);

    // Content-Length formula: plain + chunkCount*(4 + nonce12 + tag16).
    final chunkCount = (plain.length + chunkSize - 1) ~/ chunkSize;
    expect(
      wire.length,
      equals(plain.length + chunkCount * (4 + BIShareCrypto.gcmOverheadPerChunk)),
    );

    // Deliver in awkward 100 000-byte reads that split frames mid-way.
    final got = await parseBody(rx, wire, 100000);
    expect(got, equals(plain));
    expect(sha256.convert(got).toString(), equals(sha256.convert(plain).toString()));
  });

  test('single small chunk round-trips', () async {
    final (tx, rx) = await pair();
    final plain = Uint8List.fromList(utf8.encode('hello 🔐 BIShare'));
    final wire = await frameBody(tx, plain);
    final got = await parseBody(rx, wire, 7); // byte-at-a-time-ish
    expect(got, equals(plain));
  });

  test('exact multiple of chunk size has no trailing empty frame', () async {
    final (tx, rx) = await pair();
    final plain = Uint8List.fromList(List<int>.filled(chunkSize * 2, 0xAB));
    final wire = await frameBody(tx, plain);
    expect(wire.length,
        equals(plain.length + 2 * (4 + BIShareCrypto.gcmOverheadPerChunk)));
    expect(await parseBody(rx, wire, chunkSize + 5), equals(plain));
  });
}
