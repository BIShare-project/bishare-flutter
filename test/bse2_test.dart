import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:bishare/core/deeplink/deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden vectors produced by Node's WebCrypto running a byte-true mirror of
/// bishare-web/src/lib/e2e/crypto.ts (the writer) — so these tests prove
/// cross-implementation compatibility with real web uploads, not just a Dart
/// round-trip. key = 0x00..0x1f, salt = A1B2C3D4, recordSize = 8.
const _keyFragment = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
const _multiB64 =
    'QlNFMgEAAAChssPUAAAACAAAAAAAAAAa1mtQyO3rqmeiAXEZgDE7EnMiYBVGGkF2NA8jGNbp'
    'Q6x/9nTzaFO8i7nMPGvEF6atAMJfd+Fp7FyNwM3W5fD7Mw9x5zYhFA+FgvfRC8ClvO3Ft58X'
    'eCJoLCw8';
const _emptyB64 = 'QlNFMgEAAAChssPUAAAACAAAAAAAAAAALgShd/zjx6QiLb9T2+CZBQ==';

Future<File> _blob(Directory dir, String name, List<int> bytes) async {
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bse2-test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('Bse2.decodeKey', () {
    test('decodes the web base64url fragment to 32 raw bytes', () {
      final raw = Bse2.decodeKey(_keyFragment);
      expect(raw, isNotNull);
      expect(raw, Uint8List.fromList(List.generate(32, (i) => i)));
    });

    test('rejects wrong length and garbage', () {
      expect(Bse2.decodeKey('AAEC'), isNull);
      expect(Bse2.decodeKey('!!not-base64!!'), isNull);
    });
  });

  group('Bse2.decryptFile (WebCrypto golden vectors)', () {
    test('decrypts a multi-record container byte-for-byte', () async {
      final input = await _blob(tmp, 'multi.bse2', base64.decode(_multiB64));
      final out = File('${tmp.path}/multi.plain');
      final progress = <int>[];
      await Bse2.decryptFile(
        input: input,
        output: out,
        key: Bse2.decodeKey(_keyFragment)!,
        onProgress: (done, total) => progress.add(done),
      );
      expect(await out.readAsString(), 'The quick brown fox jumps!');
      expect(progress.last, 26);
    });

    test('decrypts the zero-byte container', () async {
      final input = await _blob(tmp, 'empty.bse2', base64.decode(_emptyB64));
      final out = File('${tmp.path}/empty.plain');
      await Bse2.decryptFile(
        input: input,
        output: out,
        key: Bse2.decodeKey(_keyFragment)!,
      );
      expect(await out.length(), 0);
    });

    test('wrong key fails authentication, not garbage output', () async {
      final input = await _blob(tmp, 'wrong.bse2', base64.decode(_multiB64));
      final out = File('${tmp.path}/wrong.plain');
      final badKey = Uint8List.fromList(List.filled(32, 0x42));
      expect(
        () => Bse2.decryptFile(input: input, output: out, key: badKey),
        throwsA(isA<Bse2Exception>()),
      );
    });

    test('truncated stream is detected', () async {
      final whole = base64.decode(_multiB64);
      final input =
          await _blob(tmp, 'trunc.bse2', whole.sublist(0, whole.length - 5));
      final out = File('${tmp.path}/trunc.plain');
      expect(
        () => Bse2.decryptFile(
          input: input,
          output: out,
          key: Bse2.decodeKey(_keyFragment)!,
        ),
        throwsA(isA<Bse2Exception>()),
      );
    });

    test('trailing bytes after the last record are rejected', () async {
      final input = await _blob(
        tmp,
        'trail.bse2',
        [...base64.decode(_multiB64), 0x00],
      );
      final out = File('${tmp.path}/trail.plain');
      expect(
        () => Bse2.decryptFile(
          input: input,
          output: out,
          key: Bse2.decodeKey(_keyFragment)!,
        ),
        throwsA(isA<Bse2Exception>()),
      );
    });
  });

  group('Bse2.sniff', () {
    test('recognises a container and rejects plain bytes', () async {
      final enc = await _blob(tmp, 's1', base64.decode(_emptyB64));
      final plain = await _blob(tmp, 's2', utf8.encode('hello world'));
      final short = await _blob(tmp, 's3', [0x42]);
      expect(await Bse2.sniff(enc), isTrue);
      expect(await Bse2.sniff(plain), isFalse);
      expect(await Bse2.sniff(short), isFalse);
    });
  });

  group('DeepLink #k fragment', () {
    test('https transfer link carries the key', () {
      final a = DeepLink.parse(
        'https://bishare.app/transfer/AB2C3D#k=$_keyFragment',
      );
      expect(a, isA<CloudTransferLink>());
      final link = a as CloudTransferLink;
      expect(link.code, 'AB2C3D');
      expect(link.key, _keyFragment);
    });

    test('scheme-less QR payload keeps the key out of the code', () {
      final a = DeepLink.parse('bishare.app/transfer/AB2C3D#k=$_keyFragment');
      expect(a, isA<CloudTransferLink>());
      final link = a as CloudTransferLink;
      expect(link.code, 'AB2C3D');
      expect(link.key, _keyFragment);
    });

    test('plain links still parse with no key', () {
      final a = DeepLink.parse('https://bishare.app/transfer/AB2C3D');
      expect((a as CloudTransferLink).key, isNull);
    });
  });
}
