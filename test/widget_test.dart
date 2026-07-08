import 'dart:convert';
import 'dart:typed_data';

import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('E2ECrypto (interop-critical scheme)', () {
    test('ECDH + HKDF + AES-GCM chunk round-trips between two peers', () async {
      final (alice, _) = await E2ECrypto.create();
      final (bob, _) = await E2ECrypto.create();

      final aliceToBob = await alice.deriveSession(bob.publicKeyBase64);
      final bobToAlice = await bob.deriveSession(alice.publicKeyBase64);
      expect(aliceToBob, isNotNull);
      expect(bobToAlice, isNotNull);

      final plaintext = Uint8List.fromList(
        utf8.encode('BIShare payload — 你好 🚀'),
      );
      final baseNonce = SessionCipher.generateBaseNonce();

      // Alice encrypts chunk 7; Bob (shared key) decrypts it.
      final sealed = await aliceToBob!.encryptChunk(plaintext, 7, baseNonce);
      final opened = await bobToAlice!.decryptChunk(sealed, 7, baseNonce);
      expect(opened, equals(plaintext));

      // Combined (single-shot) path.
      final c = await aliceToBob.encryptCombined(plaintext);
      final d = await bobToAlice.decryptCombined(c);
      expect(d, equals(plaintext));
    });

    test('wrong chunk index fails to decrypt', () async {
      final (alice, _) = await E2ECrypto.create();
      final (bob, _) = await E2ECrypto.create();
      final a = await alice.deriveSession(bob.publicKeyBase64);
      final b = await bob.deriveSession(alice.publicKeyBase64);

      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      final baseNonce = SessionCipher.generateBaseNonce();
      final sealed = await a!.encryptChunk(data, 1, baseNonce);
      expect(() => b!.decryptChunk(sealed, 2, baseNonce), throwsA(anything));
    });

    test('combined layout is nonce(12) | ciphertext | tag(16)', () async {
      final (alice, _) = await E2ECrypto.create();
      final (bob, _) = await E2ECrypto.create();
      final a = await alice.deriveSession(bob.publicKeyBase64);
      final data = Uint8List.fromList(List<int>.filled(100, 42));
      final c = await a!.encryptCombined(data);
      // 12 (nonce) + 100 (ciphertext == plaintext length for GCM) + 16 (tag).
      expect(c.length, equals(12 + 100 + 16));
    });

    test('fingerprint is 8 space-separated hex bytes', () async {
      final (alice, _) = await E2ECrypto.create();
      final fp = await E2ECrypto.peerFingerprint(alice.publicKeyBase64);
      final parts = fp.split(' ');
      expect(parts.length, equals(8));
      expect(parts.every((p) => RegExp(r'^[0-9A-F]{2}$').hasMatch(p)), isTrue);
    });

    test('normalizeRawKey accepts raw 32 and legacy 44-byte X.509', () {
      final raw = Uint8List.fromList(List<int>.generate(32, (i) => i));
      expect(E2ECrypto.normalizeRawKey(raw), equals(raw));

      final spki = Uint8List.fromList([
        0x30,
        0x2a,
        0x30,
        0x05,
        0x06,
        0x03,
        0x2b,
        0x65,
        0x6e,
        0x03,
        0x21,
        0x00,
        ...raw,
      ]);
      expect(E2ECrypto.normalizeRawKey(spki), equals(raw));
    });
  });
}
