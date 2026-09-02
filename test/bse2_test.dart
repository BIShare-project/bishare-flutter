import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:bishare/core/deeplink/deep_link.dart';
import 'package:bishare/core/rust/rust_facade.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

/// Golden vectors produced by Node's WebCrypto running the web writer
/// (bishare-web/src/lib/e2e/crypto.ts). The Rust module's own tests pin the
/// SAME bytes, so this file proves the Dart→Rust bridge round-trips exactly
/// what a real web upload contains. key = 0x00..0x1f, salt = A1B2C3D4,
/// recordSize = 8.
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

Uint8List _random(int n) {
  final r = Random(7);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  late Directory tmp;
  late bool rust;

  setUpAll(() async {
    rust = await initRustForTests();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bse2-test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('key codec (pure Dart, must match Rust and web)', () {
    test('decodes the web base64url fragment to 32 raw bytes', () {
      final raw = Bse2.decodeKey(_keyFragment);
      expect(raw, Uint8List.fromList(List.generate(32, (i) => i)));
      expect(Bse2.encodeKey(raw!), _keyFragment);
      expect(
        Bse2.decodeKey('$_keyFragment='),
        raw,
        reason: 'tolerates padding',
      );
    });

    test('rejects wrong length and garbage', () {
      expect(Bse2.decodeKey('AAEC'), isNull);
      expect(Bse2.decodeKey('!!not-base64!!'), isNull);
    });

    test('the deep-link parser hands the fragment key through', () {
      final action = DeepLink.parse(
        'https://bishare.app/transfer/ABCDEF#k=$_keyFragment',
      );
      expect(action, isA<CloudTransferLink>());
      expect((action! as CloudTransferLink).key, _keyFragment);
    });
  });

  group('ciphertextSize', () {
    test('mirrors the container math exactly', () {
      // header + plaintext + one tag per record; an empty file is ONE record.
      expect(Bse2.ciphertextSize(0), 24 + 0 + 16);
      expect(Bse2.ciphertextSize(1), 24 + 1 + 16);
      expect(Bse2.ciphertextSize(Bse2.recordSize), 24 + Bse2.recordSize + 16);
      expect(
        Bse2.ciphertextSize(Bse2.recordSize + 1),
        24 + Bse2.recordSize + 1 + 32,
      );
    });

    test('agrees with the Rust implementation', () {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      for (final n in [0, 1, 4095, Bse2.recordSize, Bse2.recordSize * 3 + 17]) {
        expect(
          Bse2.ciphertextSize(n),
          Rust.bse2CiphertextSize(n),
          reason: '$n',
        );
      }
    });
  });

  group('decryptFile (WebCrypto golden vectors through Rust)', () {
    test('decrypts a multi-record container byte-for-byte', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
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
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final input = await _blob(tmp, 'empty.bse2', base64.decode(_emptyB64));
      final out = File('${tmp.path}/empty.plain');
      await Bse2.decryptFile(
        input: input,
        output: out,
        key: Bse2.decodeKey(_keyFragment)!,
      );
      expect(await out.length(), 0);
    });

    test('wrong key fails authentication and leaves no output', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final input = await _blob(tmp, 'wrong.bse2', base64.decode(_multiB64));
      final out = File('${tmp.path}/wrong.plain');
      await expectLater(
        Bse2.decryptFile(
          input: input,
          output: out,
          key: Uint8List.fromList(List.filled(32, 0x42)),
        ),
        throwsA(isA<Bse2Exception>()),
      );
      expect(
        out.existsSync(),
        isFalse,
        reason: 'partial output must be removed',
      );
    });

    test('truncated stream and trailing bytes are detected', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final whole = base64.decode(_multiB64);
      final key = Bse2.decodeKey(_keyFragment)!;
      final trunc = await _blob(
        tmp,
        'trunc.bse2',
        whole.sublist(0, whole.length - 5),
      );
      await expectLater(
        Bse2.decryptFile(
          input: trunc,
          output: File('${tmp.path}/t.plain'),
          key: key,
        ),
        throwsA(isA<Bse2Exception>()),
      );
      final trail = await _blob(tmp, 'trail.bse2', [...whole, 0x00]);
      await expectLater(
        Bse2.decryptFile(
          input: trail,
          output: File('${tmp.path}/r.plain'),
          key: key,
        ),
        throwsA(isA<Bse2Exception>()),
      );
    });
  });

  group('encryptFile (Rust) → decryptFile round trip', () {
    test('seals a multi-record file the web reader would accept', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final plain = _random(Bse2.recordSize * 2 + 12345);
      final input = await _blob(tmp, 'in.bin', plain);
      final sealed = File('${tmp.path}/in.bse2');
      final key = Bse2.generateKey();
      expect(key.length, 32);

      final progress = <int>[];
      await Bse2.encryptFile(
        input: input,
        output: sealed,
        key: key,
        onProgress: (done, total) {
          expect(total, plain.length);
          progress.add(done);
        },
      );
      expect(progress, [Bse2.recordSize, Bse2.recordSize * 2, plain.length]);

      // Container shape: magic, version, record size, plaintext size, length.
      final bytes = await sealed.readAsBytes();
      expect(bytes.sublist(0, 4), Bse2.magic);
      expect(bytes[4], Bse2.version);
      final view = ByteData.sublistView(bytes);
      expect(view.getUint32(12), Bse2.recordSize);
      expect(view.getUint64(16), plain.length);
      expect(bytes.length, Bse2.ciphertextSize(plain.length));
      expect(await Bse2.sniff(sealed), isTrue);
      expect(await Bse2.sniff(input), isFalse);

      final out = File('${tmp.path}/out.bin');
      await Bse2.decryptFile(input: sealed, output: out, key: key);
      expect(await out.readAsBytes(), plain);
    });

    test('two seals of the same file differ (fresh salt per file)', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final input = await _blob(tmp, 'same.bin', utf8.encode('same bytes'));
      final key = Bse2.generateKey();
      final a = File('${tmp.path}/a.bse2');
      final b = File('${tmp.path}/b.bse2');
      await Bse2.encryptFile(input: input, output: a, key: key);
      await Bse2.encryptFile(input: input, output: b, key: key);
      expect(await a.readAsBytes(), isNot(await b.readAsBytes()));
    });

    test('an empty file seals to a lone authenticated tag', () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final input = await _blob(tmp, 'empty.bin', const []);
      final sealed = File('${tmp.path}/empty.bse2');
      final key = Bse2.generateKey();
      await Bse2.encryptFile(input: input, output: sealed, key: key);
      expect(await sealed.length(), 40);
      final out = File('${tmp.path}/empty.out');
      await Bse2.decryptFile(input: sealed, output: out, key: key);
      expect(await out.length(), 0);
    });

    test(
      'rejects a key that is not 32 bytes before touching the bridge',
      () async {
        final input = await _blob(tmp, 'x.bin', [1, 2, 3]);
        await expectLater(
          Bse2.encryptFile(
            input: input,
            output: File('${tmp.path}/x.bse2'),
            key: Uint8List(16),
          ),
          throwsA(isA<Bse2Exception>()),
        );
      },
    );
  });
}
