import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bishare/core/server/zip_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Smoke-tests the streaming zip encoder behind `/download-folder` and
/// `/api/v1/download-all`: the emitted bytes must decode with a real zip
/// reader (`package:archive`'s ZipDecoder) with names + contents intact.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bishare_zip_test');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<Uint8List> collect(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  test('a folder tree round-trips through ZipDecoder', () async {
    File(p.join(dir.path, 'root.txt')).writeAsStringSync('at the root');
    Directory(p.join(dir.path, 'Images')).createSync();
    File(p.join(dir.path, 'Images', 'a.bin'))
        .writeAsBytesSync(List<int>.generate(70000, (i) => i % 251));
    Directory(p.join(dir.path, 'Images', 'Nested')).createSync();
    File(p.join(dir.path, 'Images', 'Nested', 'deep.txt'))
        .writeAsStringSync('deep contents');
    File(p.join(dir.path, 'empty.dat')).writeAsBytesSync(const []);
    // Hidden files and .part temps must never leak into an archive.
    File(p.join(dir.path, '.browser-abc.part')).writeAsStringSync('secret');

    final entries = zipEntriesForDirectory(dir);
    expect(
      entries.map((e) => e.name),
      containsAll([
        'root.txt',
        'Images/a.bin',
        'Images/Nested/deep.txt',
        'empty.dat',
      ]),
    );
    expect(entries.any((e) => e.name.contains('.browser')), isFalse);

    final bytes = await collect(zipStream(entries));
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final byName = {for (final f in archive) f.name: f};
    expect(
      utf8.decode(byName['root.txt']!.readBytes()!.toList()),
      'at the root',
    );
    expect(
      byName['Images/a.bin']!.readBytes()!.toList(),
      List<int>.generate(70000, (i) => i % 251),
    );
    expect(
      utf8.decode(byName['Images/Nested/deep.txt']!.readBytes()!.toList()),
      'deep contents',
    );
    expect(byName['empty.dat']!.size, 0);
    expect(byName.keys.any((n) => n.contains('secret')), isFalse);
  });

  test('empty directories survive as explicit entries', () async {
    Directory(p.join(dir.path, 'Videos')).createSync();
    File(p.join(dir.path, 'x.txt')).writeAsStringSync('x');

    final entries = zipEntriesForDirectory(dir);
    expect(entries.map((e) => e.name), containsAll(['Videos/', 'x.txt']));

    final bytes = await collect(zipStream(entries));
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final names = archive.map((f) => f.name).toList();
    expect(names, contains('x.txt'));
    expect(names.any((n) => n.startsWith('Videos')), isTrue);
  });

  test('an empty listing still produces a valid (empty) archive', () async {
    final bytes = await collect(zipStream(const []));
    // 22-byte classic end-of-central-directory record only.
    expect(bytes.length, 22);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.length, 0);
  });

  test('unicode names survive the round-trip', () async {
    File(p.join(dir.path, 'фото — 写真.txt')).writeAsStringSync('unicode');
    final bytes = await collect(zipStream(zipEntriesForDirectory(dir)));
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    expect(archive.first.name, 'фото — 写真.txt');
  });
}
