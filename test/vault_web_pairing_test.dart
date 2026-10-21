import 'dart:convert';

import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:flutter_test/flutter_test.dart';

/// The browser's QR code and typed code (VAULT-SPEC "Opening the Drive in a
/// browser", task 6.11).
void main() {
  String key(int fill) =>
      base64Url.encode(List.filled(32, fill)).replaceAll('=', '');
  const slot = 'AAAAAAAAAAAAAAAAAAAAAA';

  test('a browser QR code is read, a device code is not', () {
    final raw = 'BSVW1.$slot.${key(1)}.${key(2)}';
    expect(VaultWebPairing.isWebCode(raw), isTrue);
    final qr = VaultWebPairing.parse(raw);
    expect(qr.slot, slot);
    expect(qr.boxPub, key(1));
    expect(qr.devicePub, key(2));
    expect(VaultWebPairing.isWebCode('BSVP1.$slot.${key(1)}'), isFalse);
    for (final bad in [
      'BSVP1.$slot.${key(1)}.${key(2)}',
      'BSVW1.$slot.${key(1)}',
      'BSVW1.short.${key(1)}.${key(2)}',
      'BSVW1.$slot.${key(1)}.AAAA',
      'BSVW1.$slot.${key(1)}.${key(2)}.extra',
      'https://drive.bishare.app',
    ]) {
      expect(
        () => VaultWebPairing.parse(bad),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('a typed code: any case, spaces and dots, only its alphabet', () {
    expect(VaultWebPairing.normalizeCode('k7q4 · 9mzd'), 'K7Q49MZD');
    expect(VaultWebPairing.normalizeCode('K7Q4-9MZD'), 'K7Q49MZD');
    expect(VaultWebPairing.normalizeCode('K7Q49MZ'), isNull);
    expect(VaultWebPairing.normalizeCode('K7Q49MZO'), isNull, reason: 'no O');
    expect(VaultWebPairing.normalizeCode('K7Q49MZ1'), isNull, reason: 'no 1');
    expect(VaultWebPairing.showCode('K7Q49MZD'), 'K7Q4 · 9MZD');
  });
}
