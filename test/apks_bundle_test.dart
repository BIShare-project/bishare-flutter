import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bishare/core/media/media_sources.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// An App Bundle install cannot be re-installed from its base APK alone
/// (`isSplitRequired` → INSTALL_FAILED_MISSING_SPLIT). App Share used to send
/// exactly that. These pin what it sends now.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late File base;
  late File abi;
  late File lang;

  Uint8List bytes(int seed, int length) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xff));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('apks_test_');
    base = File(p.join(dir.path, 'base.apk'))..writeAsBytesSync(bytes(1, 70000));
    abi = File(p.join(dir.path, 'split_config.arm64_v8a.apk'))..writeAsBytesSync(bytes(2, 41000));
    lang = File(p.join(dir.path, 'split_config.en.apk'))..writeAsBytesSync(bytes(3, 900));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('an app installed as one APK is still copied as a plain .apk', () async {
    final out = await MediaSources.stageApk(base.path, appName: 'My App', version: '2.24.1');
    addTearDown(() => File(out).deleteSync());
    expect(p.basename(out), 'My_App_2.24.1.apk');
    expect(File(out).readAsBytesSync(), base.readAsBytesSync());
  });

  test('a split install becomes one .apks holding the base and every split', () async {
    final out = await MediaSources.stageApk(
      base.path,
      appName: 'My App',
      version: '2.24.1',
      splitPaths: [abi.path, lang.path],
    );
    addTearDown(() => File(out).deleteSync());
    expect(p.basename(out), 'My_App_2.24.1.apks');

    // Read it back with a different zip implementation than the one that wrote it.
    final zip = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
    expect(zip.files.map((f) => f.name).toList(), [
      'base.apk',
      'split_config.arm64_v8a.apk',
      'split_config.en.apk',
    ]);
    expect(zip.findFile('base.apk')!.content, base.readAsBytesSync());
    expect(zip.findFile('split_config.arm64_v8a.apk')!.content, abi.readAsBytesSync());
    expect(zip.findFile('split_config.en.apk')!.content, lang.readAsBytesSync());
  });

  test('the base is always named base.apk, whatever its path says', () {
    final odd = File(p.join(dir.path, 'weird-name.apk'))..writeAsBytesSync(bytes(9, 10));
    final entries = MediaSources.apksEntries(odd.path, [abi.path]);
    expect(entries.first.name, 'base.apk');
    expect(entries.first.file!.path, odd.path);
  });

  test('entry names never collide', () {
    final other = Directory(p.join(dir.path, 'other'))..createSync();
    final twin = File(p.join(other.path, 'split_config.en.apk'))..writeAsBytesSync(bytes(4, 10));
    final shadow = File(p.join(other.path, 'base.apk'))..writeAsBytesSync(bytes(5, 10));
    final names = MediaSources.apksEntries(base.path, [lang.path, twin.path, shadow.path])
        .map((e) => e.name)
        .toList();
    expect(names.toSet().length, names.length);
    expect(names.first, 'base.apk');
    expect(names.every((n) => n.endsWith('.apk')), isTrue);
  });

  test('a split that vanished mid-staging leaves no half-written archive', () async {
    final gone = p.join(dir.path, 'split_config.xxhdpi.apk'); // never created
    final before = Directory.systemTemp.listSync().whereType<File>().where((f) => f.path.endsWith('.apks')).length;
    await expectLater(
      MediaSources.stageApk(base.path, appName: 'Gone', version: '1', splitPaths: [gone]),
      throwsA(isA<FileSystemException>()),
    );
    final after = Directory.systemTemp.listSync().whereType<File>().where((f) => f.path.endsWith('.apks')).length;
    expect(after, before);
  });
}
