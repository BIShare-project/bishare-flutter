// redesign 4.1: a sender attaches a small thumbnail to photos in the offer.
// On a computer the pure-Dart path resizes and encodes it.
import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/io/file_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('thumb'));
  tearDown(() => dir.delete(recursive: true));

  test('a photo becomes a JPEG of at most 120 px', () async {
    final photo = img.Image(width: 1600, height: 900);
    img.fill(photo, color: img.ColorRgb8(30, 120, 220));
    final path = '${dir.path}/IMG_1.png';
    await File(path).writeAsBytes(img.encodePng(photo));

    final b64 = await generateThumbnail(path, 'image/png');
    expect(b64, isNotNull);
    final thumb = img.decodeJpg(base64Decode(b64!))!;
    expect(thumb.width, 120);
    expect(thumb.height, lessThanOrEqualTo(120));
    // Small enough to ride in the prepare request.
    expect(b64.length, lessThan(12 * 1024));
  });

  test('a file that is not a picture has no thumbnail', () async {
    final path = '${dir.path}/notes.txt';
    await File(path).writeAsString('hello');
    expect(await generateThumbnail(path, 'text/plain'), isNull);
    // A broken image is skipped, not thrown.
    final bad = '${dir.path}/broken.jpg';
    await File(bad).writeAsBytes([1, 2, 3]);
    expect(await generateThumbnail(bad, 'image/jpeg'), isNull);
  });
}
