// Where a received file is saved and under what name: the sender's own name
// by default, `{yyyy-MM-dd}_{sender}_{name}` with the setting on, and never
// over another file (on disk, or handed out to a file still on its way).
import 'dart:io';

import 'package:bishare/core/protocol/file_metadata.dart';
import 'package:bishare/core/server/receive_naming.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

FileMetadata _meta(String name, [String type = 'image/heic']) =>
    FileMetadata(id: name, fileName: name, size: 1, fileType: type);

String _name(File f) => f.uri.pathSegments.last;

void main() {
  late bool rust;
  late Directory dir;

  setUpAll(() async => rust = await initRustForTests());
  setUp(() => dir = Directory.systemTemp.createTempSync('bishare-naming-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps the sender\'s file name by default', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final f = ReceiveNaming.targetFile(dir, _meta('IMG_4821.HEIC'), 'Leo');
    expect(_name(f), 'IMG_4821.HEIC');
    expect(f.parent.uri.pathSegments.where((s) => s.isNotEmpty).last, 'Images');
  });

  test('adds the date and sender when asked', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final f = ReceiveNaming.targetFile(
      dir,
      _meta('IMG20261110231943.jpg', 'image/jpeg'),
      'realme RMX5171',
      addSender: true,
    );
    expect(
      _name(f),
      matches(
        RegExp(r'^\d{4}-\d{2}-\d{2}_realme-RMX5171_IMG20261110231943\.jpg$'),
      ),
    );
  });

  test('a name on disk gets (1), (2)', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final first = ReceiveNaming.targetFile(dir, _meta('a.HEIC'), 'Leo')
      ..writeAsStringSync('1');
    final second = ReceiveNaming.targetFile(dir, _meta('a.HEIC'), 'Dina')
      ..writeAsStringSync('2');
    final third = ReceiveNaming.targetFile(dir, _meta('a.HEIC'), 'Leo');
    expect(_name(first), 'a.HEIC');
    expect(_name(second), 'a (1).HEIC');
    expect(_name(third), 'a (2).HEIC');
  });

  test('two files of the same name arriving together get different names', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    // Neither is on disk yet: both are still being moved into place.
    final a = ReceiveNaming.targetFile(dir, _meta('IMG_0001.HEIC'), 'Leo');
    final b = ReceiveNaming.targetFile(dir, _meta('IMG_0001.HEIC'), 'Leo');
    expect(_name(a), 'IMG_0001.HEIC');
    expect(_name(b), 'IMG_0001 (1).HEIC');
  });

  test('an iPhone photo export name arrives as the photo\'s own name', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    // What iOS senders before 2.8.2 sent (photo_manager's export file name).
    final f = ReceiveNaming.targetFile(
      dir,
      _meta(
        '6E5438ED-9A8C-4ED0-9DEA-AB2D8F8A9360_L0_001_1762851000.123456_o_IMG_4821.HEIC',
      ),
      'iPhone',
    );
    expect(_name(f), 'IMG_4821.HEIC');
  });

  test('unwrapPhotoExport leaves ordinary names alone', () {
    expect(ReceiveNaming.unwrapPhotoExport('IMG_4821.HEIC'), 'IMG_4821.HEIC');
    expect(
      ReceiveNaming.unwrapPhotoExport('2026-11-11_Leo_IMG_1.jpg'),
      '2026-11-11_Leo_IMG_1.jpg',
    );
    expect(
      ReceiveNaming.unwrapPhotoExport(
        '6E5438ED-9A8C-4ED0-9DEA-AB2D8F8A9360_L0_001_1762851000.5_IMG_9.MOV',
      ),
      'IMG_9.MOV',
    );
  });

  test('an opaque photo-library token still gets a readable name', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final f = ReceiveNaming.targetFile(
      dir,
      _meta('AQMBofb1w6Z0IrAQMBofb1w6Z0IrAQMBofb1w6Z0Ir.mp4', 'video/mp4'),
      'Leo',
    );
    expect(_name(f), matches(RegExp(r'^Video_\d{8}_\d{6}_Leo\.mp4$')));
  });

  test('replace: the plain name, over the file already there', () {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final images = Directory('${dir.path}/Images')..createSync();
    File('${images.path}/b.HEIC').writeAsStringSync('old');
    expect(ReceiveNaming.clashes(dir, _meta('b.HEIC'), 'Leo'), isTrue);
    expect(ReceiveNaming.clashes(dir, _meta('c.HEIC'), 'Leo'), isFalse);
    final claimed = <String>{};
    final f = ReceiveNaming.targetFile(
      dir,
      _meta('b.HEIC'),
      'Leo',
      replace: true,
      claimed: claimed,
    );
    expect(_name(f), 'b.HEIC');
    // The same name again in the same transfer is kept apart.
    final g = ReceiveNaming.targetFile(
      dir,
      _meta('b.HEIC'),
      'Leo',
      replace: true,
      claimed: claimed,
    );
    expect(_name(g), 'b (1).HEIC');
  });
}
