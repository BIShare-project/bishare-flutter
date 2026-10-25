// redesign-plan.md 3.2: the Send tab's selection keeps one order across
// tabs, mirrors the tray, and turns gallery items into files only when
// sending.
import 'dart:io';

import 'package:bishare/features/send/data/send_media_library.dart';
import 'package:bishare/features/send/presentation/send_selection_cubit.dart';
import 'package:bishare/features/send/presentation/tray_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A library whose originals are small files in a temp folder.
class _FakeLibrary extends SendMediaLibrary {
  _FakeLibrary(this.dir);
  final Directory dir;
  final exported = <String>[];

  @override
  Future<File?> original(AssetEntity a) async {
    exported.add(a.id);
    final f = File('${dir.path}/VID_${a.id}.mp4');
    await f.writeAsBytes(List.filled(1000 + int.parse(a.id), 1));
    return f;
  }

  @override
  Future<int?> sizeOf(AssetEntity a) async => null;
}

AssetEntity _video(String id) =>
    AssetEntity(id: id, typeInt: AssetType.video.index, width: 10, height: 10);

void main() {
  late Directory dir;
  late TrayCubit tray;
  late _FakeLibrary lib;
  late SendSelectionCubit sel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('sel');
    tray = TrayCubit(await SharedPreferences.getInstance());
    lib = _FakeLibrary(dir);
    sel = SendSelectionCubit(tray, library: lib);
  });

  tearDown(() async {
    await sel.close();
    await tray.close();
    await dir.delete(recursive: true);
  });

  Future<String> file(String name, [int size = 10]) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(List.filled(size, 0));
    return f.path;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('one order across tabs, numbered from 1', () async {
    sel.toggleAsset(_video('1'), SendKind.video);
    tray.addPaths([await file('a.pdf')]);
    await settle();
    sel.toggleAsset(_video('2'), SendKind.video);

    expect(sel.state.length, 3);
    expect(sel.state.orderOf('a:1'), 1);
    expect(sel.state.orderOfPath('${dir.path}/a.pdf'), 2);
    expect(sel.state.orderOf('a:2'), 3);
    expect(sel.state.countOf(SendKind.video), 2);
    expect(sel.state.countOf(SendKind.doc), 1);
  });

  test('a tab hint wins over the file type', () async {
    sel.hintNext(SendKind.more);
    tray.addPaths([await file('note.txt')]);
    await settle();
    expect(sel.state.countOf(SendKind.more), 1);
    expect(sel.state.countOf(SendKind.doc), 0);
  });

  test('a day select and unselect', () {
    final day = [_video('1'), _video('2'), _video('3')];
    sel.setAssets(day, SendKind.video, true);
    expect(sel.state.length, 3);
    sel.setAssets(day.sublist(1), SendKind.video, false);
    expect(sel.state.length, 1);
    expect(sel.state.orderOf('a:1'), 1);
  });

  test('removing from the tray removes from the selection, and back', () async {
    final p = await file('b.pdf');
    sel.toggleFile(p, SendKind.doc);
    await settle();
    expect(sel.isFileSelected(p), isTrue);
    sel.toggleFile(p, SendKind.doc);
    await settle();
    expect(sel.state.isEmpty, isTrue);
    expect(tray.state, isEmpty);
  });

  test('sizes are unknown until every item has one', () async {
    tray.addPaths([await file('c.pdf', 300)]);
    await settle();
    expect(sel.state.bytes, 300);
    sel.toggleAsset(_video('9'), SendKind.video);
    expect(sel.state.bytes, isNull);
  });

  test(
    'nothing is exported while selecting; materialize keeps the order',
    () async {
      sel.toggleAsset(_video('1'), SendKind.video);
      tray.addPaths([await file('d.pdf')]);
      await settle();
      sel.toggleAsset(_video('2'), SendKind.video);
      expect(lib.exported, isEmpty);

      final out = await sel.materialize();
      expect(lib.exported, ['1', '2']);
      expect(out.map((f) => f.name), ['VID_1.mp4', 'd.pdf', 'VID_2.mp4']);
      expect(tray.state.map((f) => f.name), [
        'VID_1.mp4',
        'd.pdf',
        'VID_2.mp4',
      ]);
      expect(sel.state.length, 3);
      expect(sel.state.bytes, isNotNull);
    },
  );

  test('clear empties both the selection and the tray', () async {
    sel.toggleAsset(_video('1'), SendKind.video);
    tray.addPaths([await file('e.pdf')]);
    await settle();
    sel.clear();
    await settle();
    expect(sel.state.isEmpty, isTrue);
    expect(tray.state, isEmpty);
  });
}
