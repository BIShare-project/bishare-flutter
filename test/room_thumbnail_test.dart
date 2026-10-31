import 'dart:convert';
import 'dart:math';

import 'package:bishare/core/io/file_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('a small preview goes as it is', () async {
    expect(await fitRoomThumbnail(null), isNull);
    expect(await fitRoomThumbnail('abc'), 'abc');
  });

  test('a preview too big for the room header is made smaller', () async {
    // Noise compresses worst: a 120x260 phone-screenshot preview like the one
    // that was refused with ROOM_ENCRYPTION_REQUIRED.
    final r = Random(1);
    final im = img.Image(width: 120, height: 260);
    for (final p in im) {
      p.setRgb(r.nextInt(256), r.nextInt(256), r.nextInt(256));
    }
    final big = base64Encode(img.encodeJpg(im, quality: 70));
    expect(big.length, greaterThanOrEqualTo(6000));
    final fitted = await fitRoomThumbnail(big);
    if (fitted != null) {
      expect(fitted.length, lessThan(6000));
      final out = img.decodeJpg(base64Decode(fitted))!;
      expect(max(out.width, out.height), 96);
    }
  });
}
