// Where received files go by type (ReceiveFolders): the type subfolders of
// the save folder by default, everything together with sorting off, or a
// folder the person chose for a type, falling back when that folder is gone.
import 'dart:io';

import 'package:bishare/core/protocol/file_metadata.dart';
import 'package:bishare/core/server/receive_folders.dart';
import 'package:bishare/core/server/receive_naming.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

FileMetadata _meta(String name, String type) =>
    FileMetadata(id: name, fileName: name, size: 1, fileType: type);

String _last(Directory d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last;

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bishare-folders-');
    ReceiveFolders.sortByType = true;
    ReceiveFolders.custom = const {};
  });
  tearDown(() {
    ReceiveFolders.sortByType = true;
    ReceiveFolders.custom = const {};
    dir.deleteSync(recursive: true);
  });

  group('categoryOf', () {
    test('photos, videos and audio by MIME type', () {
      expect(
        ReceiveFolders.categoryOf('IMG_4821.HEIC', 'image/heic'),
        'Images',
      );
      expect(
        ReceiveFolders.categoryOf('clip.MOV', 'video/quicktime'),
        'Videos',
      );
      expect(ReceiveFolders.categoryOf('song.m4a', 'audio/mp4'), 'Audio');
    });

    test('apps get their own folder (an APK used to land in Archives)', () {
      expect(
        ReceiveFolders.categoryOf(
          'app.apk',
          'application/vnd.android.package-archive',
        ),
        'Apps',
      );
      expect(ReceiveFolders.categoryOf('setup.exe', null), 'Apps');
      expect(ReceiveFolders.categoryOf('BIShare.dmg', ''), 'Apps');
      expect(
        ReceiveFolders.categoryOf('game.xapk', 'application/octet-stream'),
        'Apps',
      );
    });

    test('office files are documents (a .docx used to land in Other)', () {
      expect(
        ReceiveFolders.categoryOf(
          'report.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        ),
        'Documents',
      );
      expect(ReceiveFolders.categoryOf('sheet.xlsx', null), 'Documents');
      expect(
        ReceiveFolders.categoryOf('scan.pdf', 'application/pdf'),
        'Documents',
      );
      expect(ReceiveFolders.categoryOf('notes.txt', 'text/plain'), 'Documents');
    });

    test('archives and everything else', () {
      expect(
        ReceiveFolders.categoryOf('photos.zip', 'application/zip'),
        'Archives',
      );
      expect(ReceiveFolders.categoryOf('backup.7z', null), 'Archives');
      expect(
        ReceiveFolders.categoryOf('data.bin', 'application/octet-stream'),
        'Other',
      );
    });
  });

  group('dirFor', () {
    test('a type subfolder of the save folder by default', () {
      final d = ReceiveFolders.dirFor(dir, 'IMG_1.HEIC', 'image/heic');
      expect(_last(d), 'Images');
      expect(d.parent.path, dir.path);
      expect(d.existsSync(), isTrue);
    });

    test('the save folder itself when sorting by type is off', () {
      ReceiveFolders.sortByType = false;
      expect(
        ReceiveFolders.dirFor(dir, 'IMG_1.HEIC', 'image/heic').path,
        dir.path,
      );
    });

    test('the folder chosen for the type; other types unchanged', () {
      final mine = Directory('${dir.path}/My photos');
      ReceiveFolders.custom = {'Images': mine.path};
      expect(
        ReceiveFolders.dirFor(dir, 'IMG_1.HEIC', 'image/heic').path,
        mine.path,
      );
      expect(mine.existsSync(), isTrue);
      expect(
        _last(ReceiveFolders.dirFor(dir, 'clip.MOV', 'video/quicktime')),
        'Videos',
      );
    });

    test(
      'falls back to the subfolder when the chosen folder cannot be made',
      () {
        // A path under a FILE cannot become a folder.
        final blocker = File('${dir.path}/not-a-folder')
          ..writeAsStringSync('x');
        ReceiveFolders.custom = {'Images': '${blocker.path}/photos'};
        final d = ReceiveFolders.dirFor(dir, 'IMG_1.HEIC', 'image/heic');
        expect(_last(d), 'Images');
        expect(d.parent.path, dir.path);
      },
    );
  });

  group('ReceiveNaming follows the setting', () {
    late bool rust;
    setUpAll(() async => rust = await initRustForTests());

    test('targetFile and clashes use the chosen folder', () {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final mine = Directory('${dir.path}/Docs here');
      ReceiveFolders.custom = {'Documents': mine.path};
      final meta = _meta(
        'report.docx',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
      final f = ReceiveNaming.targetFile(dir, meta, 'Leo');
      expect(f.parent.path, mine.path);
      expect(ReceiveNaming.clashes(dir, meta, 'Leo'), isFalse);
      f.writeAsStringSync('x');
      expect(ReceiveNaming.clashes(dir, meta, 'Leo'), isTrue);
    });

    test('targetFile puts everything together with sorting off', () {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      ReceiveFolders.sortByType = false;
      final f = ReceiveNaming.targetFile(
        dir,
        _meta('app.apk', 'application/vnd.android.package-archive'),
        'Leo',
      );
      expect(f.parent.path, dir.path);
    });

    test('Replace overwrites in the chosen folder too', () {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final mine = Directory('${dir.path}/Pics');
      ReceiveFolders.custom = {'Images': mine.path};
      // A file from an earlier transfer, already in the chosen folder.
      final meta = _meta('IMG_2.HEIC', 'image/heic');
      final first = File('${mine.path}/IMG_2.HEIC')
        ..createSync(recursive: true)
        ..writeAsStringSync('old');
      final second = ReceiveNaming.targetFile(
        dir,
        meta,
        'Leo',
        replace: true,
        claimed: {},
      );
      expect(second.path, first.path);
    });
  });
}
