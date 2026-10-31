import 'package:bishare/core/network/header_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plain ASCII goes as it is', () {
    expect(headerText('Web Tester'), 'Web Tester');
    expect(headerText('icon-512.png'), 'icon-512.png');
  });

  test('a Mac default name and other scripts are encoded, and come back', () {
    for (final name in [
      'cakra’s Mac mini',
      '写真 2026.png',
      'ملف.txt',
      'Gäst',
      '50%',
    ]) {
      final sent = headerText(name);
      expect(
        sent.codeUnits.every((c) => c >= 0x20 && c <= 0x7e),
        isTrue,
        reason: name,
      );
      expect(decodeHeaderText(sent), name);
    }
  });

  test('a stray % from an older client is kept', () {
    expect(decodeHeaderText('100%.txt'), '100%.txt');
    expect(decodeHeaderText('Web%20Tester'), 'Web Tester');
    expect(decodeHeaderText(null), isNull);
  });
}
