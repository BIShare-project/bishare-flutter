import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/constants/protocol.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/io/preserve_mtime.dart';
import 'package:bishare/core/protocol/device_info.dart';
import 'package:bishare/core/protocol/file_metadata.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/server/transfer_types.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:bishare/features/send/data/transfer_client.dart';
import 'package:bishare/features/send/domain/sendable_file.dart';
import 'package:bishare/features/settings/domain/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';
import 'helpers/start_server.dart';

/// A sender-side timestamp that no test machine's clock is anywhere near, so
/// "preserved" and "stamped with now" can never be confused: 2024-07-03.
const int kMtime = 1720000000123;

/// Filesystems differ in timestamp resolution (APFS/ext4/NTFS keep the
/// millisecond; FAT and some network shares do not), so equality is asserted
/// at the second, which every one of them keeps.
int seconds(int ms) => ms ~/ 1000;

class _Identity implements DeviceIdentity {
  _Identity(this.fingerprint, this._alias);
  @override
  final String fingerprint;
  final String _alias;
  @override
  String get alias => _alias;
  @override
  String get deviceType => 'desktop';

  // No public key → the session is plaintext, which keeps this test about the
  // metadata path and off the Rust crypto engine.
  @override
  Future<DeviceInfo> makeDeviceInfo() async => DeviceInfo(
    alias: _alias,
    version: BIShareConfig.version,
    fingerprint: fingerprint,
    port: BISharePort.main,
    deviceModel: 'test',
    deviceType: 'desktop',
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('preserve_mtime helpers', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bishare-mtime-');
    });
    tearDown(() => dir.delete(recursive: true));

    test('applyReceivedMtime stamps the file with the sender time', () async {
      final f = File('${dir.path}/a.bin')..writeAsBytesSync([1, 2, 3]);
      await applyReceivedMtime(f, kMtime);
      expect(
        seconds(f.lastModifiedSync().millisecondsSinceEpoch),
        seconds(kMtime),
      );
    });

    test('mtimeOf reads back what applyReceivedMtime wrote', () async {
      final f = File('${dir.path}/b.bin')..writeAsBytesSync([1]);
      await applyReceivedMtime(f, kMtime);
      expect(seconds(mtimeOf(f)!), seconds(kMtime));
    });

    test('null and garbage leave the write time alone', () async {
      final f = File('${dir.path}/c.bin')..writeAsBytesSync([1]);
      final before = f.lastModifiedSync();
      for (final v in [null, 0, -1, 32503680000000, 1 << 62]) {
        await applyReceivedMtime(f, v);
        expect(f.lastModifiedSync(), before, reason: 'value $v');
      }
    });

    test('isUsableMtime bounds', () {
      expect(isUsableMtime(null), isFalse);
      expect(isUsableMtime(-1), isFalse);
      expect(isUsableMtime(0), isFalse); // 0 = "unknown" on every sender
      expect(isUsableMtime(kMtime), isTrue);
      expect(isUsableMtime(32503679999999), isTrue);
      expect(isUsableMtime(32503680000000), isFalse); // year 3000
    });

    test('a missing file yields null, not an exception', () {
      expect(mtimeOf(File('${dir.path}/nope')), isNull);
    });
  });

  group('FileMetadata wire format', () {
    test('mtimeMs round-trips and is omitted when absent', () {
      const withTime = FileMetadata(
        id: 'f1',
        fileName: 'a.txt',
        size: 1,
        fileType: 'text/plain',
        mtimeMs: kMtime,
      );
      final json =
          jsonDecode(jsonEncode(withTime.toJson())) as Map<String, dynamic>;
      expect(json['mtimeMs'], kMtime);
      expect(FileMetadata.fromJson(json).mtimeMs, kMtime);

      // What a 2.5.8 sender puts on the wire — must parse, and must stay
      // byte-for-byte free of the new key when re-serialised.
      final legacy = FileMetadata.fromJson(
        jsonDecode(
              '{"id":"f1","fileName":"a.txt","size":1,"fileType":"text/plain"}',
            )
            as Map<String, dynamic>,
      );
      expect(legacy.mtimeMs, isNull);
      expect(legacy.toJson().containsKey('mtimeMs'), isFalse);
    });

    test('SendableFile.fromPath carries the file mtime', () async {
      final dir = await Directory.systemTemp.createTemp('bishare-sf-');
      try {
        final f = File('${dir.path}/photo.jpg')..writeAsBytesSync([0xff, 0xd8]);
        await applyReceivedMtime(f, kMtime);
        final s = SendableFile.fromPath(f.path, id: 'x');
        expect(seconds(s.mtimeMs!), seconds(kMtime));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('LAN transfer end to end (TCP)', () {
    late bool rust;
    late Directory saveDir;
    late Directory srcDir;
    late TransferServer server;

    setUpAll(() async {
      rust = await initRustForTests();
    });

    setUp(() async {
      saveDir = await Directory.systemTemp.createTemp('bishare-recv-');
      srcDir = await Directory.systemTemp.createTemp('bishare-send-');
      server = TransferServer(
        identity: _Identity('recv-fp', 'Receiver'),
        saveDirectory: saveDir,
      )..autoAccept = AutoAcceptMode.acceptAll;
      await startServerWhenFree(server);
    });

    tearDown(() async {
      await server.stop();
      await saveDir.delete(recursive: true);
      await srcDir.delete(recursive: true);
    });

    Future<ReceivedFile> sendOne(SendableFile file) async {
      final client = TransferClient(_Identity('send-fp', 'Sender'))
        ..preferredTransport = TransportMode.tcp;
      final received = server.received.first;
      await client.send(
        [file],
        DiscoveredDevice(
          fingerprint: 'recv-fp',
          alias: 'Receiver',
          host: '127.0.0.1',
          port: BISharePort.main,
          lastSeen: DateTime.now(),
          firstSeen: DateTime.now(),
          version: BIShareConfig.version,
        ),
      );
      return received.timeout(const Duration(seconds: 20));
    }

    test('the saved file keeps the sender\'s Date modified', () async {
      if (!rust) {
        markTestSkipped(
          'native library not built (cargo build --manifest-path rust/Cargo.toml)',
        );
        return;
      }
      final src = File('${srcDir.path}/report.pdf')
        ..writeAsBytesSync(List<int>.generate(70000, (i) => i & 0xff));
      await applyReceivedMtime(src, kMtime);

      final got = await sendOne(SendableFile.fromPath(src.path, id: 'f1'));
      final saved = File(got.savedPath);
      expect(saved.existsSync(), isTrue);
      expect(saved.lengthSync(), 70000);
      expect(
        seconds(saved.lastModifiedSync().millisecondsSinceEpoch),
        seconds(kMtime),
        reason: 'receiver must stamp the original mtime, not the receive time',
      );
    });

    test('a browser upload (web share page) keeps X-File-Mtime', () async {
      if (!rust) {
        markTestSkipped('native library not built');
        return;
      }
      // What the embedded page's JS sends: one chunk, flagged complete, with
      // the File's lastModified riding on the same request.
      final received = server.received.first;
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${BISharePort.main}${BIShareApi.browserUploadChunk}',
          ),
        );
        req.headers
          ..set('x-upload-id', '11111111-2222-4333-8444-555555555555')
          ..set('x-chunk-offset', '0')
          ..set('x-file-name', 'from-browser.txt')
          ..set('x-file-size', '5')
          ..set('x-file-type', 'text/plain')
          ..set('x-file-mtime', '$kMtime')
          ..set('x-upload-complete', '1')
          ..contentLength = 5;
        req.add([104, 101, 108, 108, 111]);
        final res = await req.close();
        expect(res.statusCode, 200);
        await res.drain<void>();
      } finally {
        client.close();
      }
      final got = await received.timeout(const Duration(seconds: 10));
      final saved = File(got.savedPath);
      expect(saved.readAsStringSync(), 'hello');
      expect(
        seconds(saved.lastModifiedSync().millisecondsSinceEpoch),
        seconds(kMtime),
      );
    });

    test(
      'a sender without mtime (older app) still lands with a sane time',
      () async {
        if (!rust) {
          markTestSkipped('native library not built');
          return;
        }
        final src = File('${srcDir.path}/old.bin')..writeAsBytesSync([1, 2, 3]);
        final got = await sendOne(
          SendableFile(
            id: 'f2',
            path: src.path,
            name: 'old.bin',
            size: 3,
            mimeType: 'application/octet-stream',
            // mtimeMs deliberately absent, as a 2.5.8 sender would send it
          ),
        );
        final saved = File(got.savedPath);
        final age = DateTime.now().difference(saved.lastModifiedSync());
        expect(
          age.inSeconds.abs() < 60,
          isTrue,
          reason: 'falls back to the write time',
        );
      },
    );

    // Received names (a user's report, Nov 2026): IMG_4821.HEIC must arrive
    // as IMG_4821.HEIC, byte for byte; the date-and-sender prefix only when
    // the receiver turned it on.
    test('a photo keeps its name and its bytes', () async {
      if (!rust) {
        markTestSkipped('native library not built');
        return;
      }
      final bytes = List<int>.generate(90000, (i) => (i * 31) & 0xff);
      final src = File('${srcDir.path}/IMG_4821.HEIC')..writeAsBytesSync(bytes);
      final got = await sendOne(SendableFile.fromPath(src.path, id: 'p1'));
      final saved = File(got.savedPath);
      expect(saved.uri.pathSegments.last, 'IMG_4821.HEIC');
      expect(got.fileName, 'IMG_4821.HEIC');
      expect(saved.readAsBytesSync(), bytes);
    });

    test(
      'the same name twice: the second does not overwrite the first',
      () async {
        if (!rust) {
          markTestSkipped('native library not built');
          return;
        }
        final a = File('${srcDir.path}/IMG_0001.HEIC')..writeAsBytesSync([1]);
        final first = await sendOne(SendableFile.fromPath(a.path, id: 'p2'));
        a.writeAsBytesSync([2]);
        final second = await sendOne(SendableFile.fromPath(a.path, id: 'p3'));
        expect(File(first.savedPath).uri.pathSegments.last, 'IMG_0001.HEIC');
        expect(
          File(second.savedPath).uri.pathSegments.last,
          'IMG_0001 (1).HEIC',
        );
        expect(File(first.savedPath).readAsBytesSync(), [1]);
        expect(File(second.savedPath).readAsBytesSync(), [2]);
      },
    );

    test('with the setting on, the date and sender lead the name', () async {
      if (!rust) {
        markTestSkipped('native library not built');
        return;
      }
      server.nameWithSender = true;
      final src = File('${srcDir.path}/IMG_4822.HEIC')..writeAsBytesSync([7]);
      final got = await sendOne(SendableFile.fromPath(src.path, id: 'p4'));
      expect(
        File(got.savedPath).uri.pathSegments.last,
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}_Sender_IMG_4822\.HEIC$')),
      );
    });

    test('"Replace": the second file takes the place of the first', () async {
      if (!rust) {
        markTestSkipped('native library not built');
        return;
      }
      server.nameClash = NameClash.replace;
      final a = File('${srcDir.path}/IMG_0005.HEIC')..writeAsBytesSync([1]);
      final first = await sendOne(SendableFile.fromPath(a.path, id: 'r1'));
      // A name handed out moments ago counts as still being moved in.
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      a.writeAsBytesSync([2, 2]);
      final second = await sendOne(SendableFile.fromPath(a.path, id: 'r2'));
      expect(second.savedPath, first.savedPath);
      expect(File(second.savedPath).readAsBytesSync(), [2, 2]);
      final names = Directory(File(first.savedPath).parent.path)
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('IMG_0005'))
          .toList();
      expect(names, ['IMG_0005.HEIC']);
    });

    test('"Replace" never replaces a file of the same transfer', () async {
      if (!rust) {
        markTestSkipped('native library not built');
        return;
      }
      server.nameClash = NameClash.replace;
      final d1 = Directory('${srcDir.path}/one')..createSync();
      final d2 = Directory('${srcDir.path}/two')..createSync();
      final a = File('${d1.path}/IMG_0006.HEIC')..writeAsBytesSync([1]);
      final b = File('${d2.path}/IMG_0006.HEIC')..writeAsBytesSync([2]);
      final got = <ReceivedFile>[];
      final sub = server.received.listen(got.add);
      final client = TransferClient(_Identity('send-fp', 'Sender'))
        ..preferredTransport = TransportMode.tcp;
      await client.send(
        [
          SendableFile.fromPath(a.path, id: 's1'),
          SendableFile.fromPath(b.path, id: 's2'),
        ],
        DiscoveredDevice(
          fingerprint: 'recv-fp',
          alias: 'Receiver',
          host: '127.0.0.1',
          port: BISharePort.main,
          lastSeen: DateTime.now(),
          firstSeen: DateTime.now(),
          version: BIShareConfig.version,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();
      expect(got, hasLength(2));
      expect(got.map((r) => r.savedPath).toSet(), hasLength(2));
      expect(
        got.map((r) => File(r.savedPath).readAsBytesSync().single).toSet(),
        {1, 2},
      );
    });

    test('"Ask": the prompt counts clashes and its answer is kept', () async {
      if (!rust) {
        markTestSkipped('native library not built');
        return;
      }
      final a = File('${srcDir.path}/IMG_0007.HEIC')..writeAsBytesSync([1]);
      final first = await sendOne(SendableFile.fromPath(a.path, id: 'k1'));
      // Still auto-accepting everyone (setUp): a clash asks anyway.
      server.nameClash = NameClash.ask;
      var clashes = -1;
      final offer = server.incoming.listen((p) {
        clashes = p.clashes;
        p
          ..replaceExisting = true
          ..accept();
      });
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      a.writeAsBytesSync([3]);
      final second = await sendOne(SendableFile.fromPath(a.path, id: 'k2'));
      await offer.cancel();
      expect(clashes, 1);
      expect(second.savedPath, first.savedPath);
      expect(File(second.savedPath).readAsBytesSync(), [3]);
    });
  });
}
