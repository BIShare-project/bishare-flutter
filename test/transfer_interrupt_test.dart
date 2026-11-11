import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/constants/protocol.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/protocol/device_info.dart';
import 'package:bishare/core/protocol/file_metadata.dart';
import 'package:bishare/core/protocol/prepare.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/server/transfer_types.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:bishare/features/send/data/transfer_client.dart';
import 'package:bishare/features/send/domain/sendable_file.dart';
import 'package:bishare/features/settings/domain/settings.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';
import 'helpers/start_server.dart';

/// A transfer cut off midway (the sender's screen locked, the app went to the
/// background) must not block the next one: a user's report said a resend
/// only worked after restarting the app on both phones.
class _Identity implements DeviceIdentity {
  _Identity(this.fingerprint, this._alias);
  @override
  final String fingerprint;
  final String _alias;
  @override
  String get alias => _alias;
  @override
  String get deviceType => 'phone';

  @override
  Future<DeviceInfo> makeDeviceInfo() async => DeviceInfo(
    alias: _alias,
    version: BIShareConfig.version,
    fingerprint: fingerprint,
    port: BISharePort.main,
    deviceModel: 'test',
    deviceType: 'phone',
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _receiver = DiscoveredDevice(
  fingerprint: 'recv-fp',
  alias: 'Receiver',
  host: '127.0.0.1',
  port: BISharePort.main,
  lastSeen: DateTime.now(),
  firstSeen: DateTime.now(),
  version: BIShareConfig.version,
);

/// Opens a session the way a sender does, then never uploads: what the
/// receiver sees when the sender is suspended right after accepting.
Future<int> _abandonedPrepare(String fingerprint) async {
  final info = await _Identity(fingerprint, 'Phone').makeDeviceInfo();
  final body = PrepareRequest(
    info: info,
    files: const {
      'f1': FileMetadata(
        id: 'f1',
        fileName: 'IMG_0001.HEIC',
        size: 1000,
        fileType: 'image/heic',
      ),
    },
  ).toJson();
  final http = HttpClient();
  try {
    final req = await http.postUrl(
      Uri.parse('http://127.0.0.1:${BISharePort.main}${BIShareApi.prepare}'),
    );
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    http.close();
  }
}

/// The offer a resuming sender makes for [files] (same metadata as
/// TransferClient builds), straight over HTTP.
Future<Map<String, dynamic>> _rawPrepare(List<SendableFile> files) async {
  final info = await _Identity('send-fp', 'Phone').makeDeviceInfo();
  final body = PrepareRequest(
    info: info,
    tcpResume: true,
    files: {
      for (final f in files)
        f.id: FileMetadata(
          id: f.id,
          fileName: f.name,
          size: f.size,
          fileType: f.mimeType,
          sha256: sha256.convert(f.file.readAsBytesSync()).toString(),
          mtimeMs: f.mtimeMs,
        ),
    },
  ).toJson();
  final http = HttpClient();
  try {
    final req = await http.postUrl(
      Uri.parse('http://127.0.0.1:${BISharePort.main}${BIShareApi.prepare}'),
    );
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    return jsonDecode(await res.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  } finally {
    http.close();
  }
}

/// Starts an upload of [f] and drops the connection after [cut] bytes: the
/// sender's phone locking mid-file.
Future<void> _cutUpload(
  Map<String, dynamic> prep,
  SendableFile f,
  int cut,
) async {
  final token = (prep['files'] as Map)[f.id];
  final socket = await Socket.connect('127.0.0.1', BISharePort.main);
  socket.write(
    'POST ${BIShareApi.upload}?sessionId=${prep['sessionId']}'
    '&fileId=${f.id}&token=$token HTTP/1.1\r\n'
    'Host: 127.0.0.1\r\n'
    'Content-Type: application/octet-stream\r\n'
    'Content-Length: ${f.size}\r\n\r\n',
  );
  socket.add(f.file.readAsBytesSync().sublist(0, cut));
  await socket.flush();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  socket.destroy();
  await Future<void>.delayed(const Duration(milliseconds: 300));
}

void main() {
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

  SendableFile photo() {
    final f = File('${srcDir.path}/IMG_0001.HEIC')
      ..writeAsBytesSync(List<int>.generate(50000, (i) => i & 0xff));
    return SendableFile.fromPath(f.path, id: 'f1');
  }

  test('the same sender can send again after an interrupted transfer', () async {
    if (!rust) {
      markTestSkipped('native library not built');
      return;
    }
    expect(await _abandonedPrepare('send-fp'), 200);
    expect(server.isReceiving, isTrue);

    // The user unlocks the phone and taps Send again, well inside the 30 s
    // idle reaper window.
    await Future<void>.delayed(const Duration(seconds: 4));
    final received = server.received.first;
    final client = TransferClient(_Identity('send-fp', 'Phone'))
      ..preferredTransport = TransportMode.tcp;
    final sending = client.send([photo()], _receiver);
    expect(client.isSending, isTrue);
    await sending;
    expect(client.isSending, isFalse);

    final got = await received.timeout(const Duration(seconds: 20));
    expect(File(got.savedPath).lengthSync(), 50000);
    expect(server.isReceiving, isFalse);
  });

  test('another sender still gets "busy" while a session is open', () async {
    if (!rust) {
      markTestSkipped('native library not built');
      return;
    }
    expect(await _abandonedPrepare('send-fp'), 200);
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(await _abandonedPrepare('other-fp'), BIShareStatus.busy);
  });

  test('a cut-off file continues from where it stopped', () async {
    if (!rust) {
      markTestSkipped('native library not built');
      return;
    }
    final src = File('${srcDir.path}/VID_0001.MOV')
      ..writeAsBytesSync(List<int>.generate(3 << 20, (i) => (i * 7) & 0xff));
    final f = SendableFile.fromPath(src.path, id: 'f1');
    final prep = await _rawPrepare([f]);
    expect(prep['resumeFrom'], isEmpty);
    await _cutUpload(prep, f, 1 << 20);

    await Future<void>.delayed(const Duration(seconds: 4));
    final received = server.received.first;
    final client = TransferClient(_Identity('send-fp', 'Phone'))
      ..preferredTransport = TransportMode.tcp;
    var maxSent = 0;
    var firstSent = -1;
    await client.send(
      [f],
      _receiver,
      onProgress: (_, _, _, sent, _) {
        if (firstSent < 0) firstSent = sent;
        if (sent > maxSent) maxSent = sent;
      },
    );
    final got = await received.timeout(const Duration(seconds: 20));
    final saved = File(got.savedPath);
    expect(saved.path.endsWith('VID_0001.MOV'), isTrue);
    expect(
      sha256.convert(saved.readAsBytesSync()),
      sha256.convert(src.readAsBytesSync()),
      reason: 'byte for byte, start kept + rest sent',
    );
    expect(firstSent, greaterThanOrEqualTo(1 << 20), reason: 'resumed');
    expect(maxSent, 3 << 20);
    expect(
      saveDir.listSync(recursive: true).where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('files that already arrived are not sent twice', () async {
    if (!rust) {
      markTestSkipped('native library not built');
      return;
    }
    final a = File('${srcDir.path}/IMG_0001.JPG')
      ..writeAsBytesSync(List<int>.generate(40000, (i) => i & 0xff));
    final b = File('${srcDir.path}/IMG_0002.JPG')
      ..writeAsBytesSync(List<int>.generate(60000, (i) => (i * 3) & 0xff));
    final fa = SendableFile.fromPath(a.path, id: 'a');
    final fb = SendableFile.fromPath(b.path, id: 'b');
    final prep = await _rawPrepare([fa, fb]);
    // The first photo arrives whole, then the sender is cut off.
    final token = (prep['files'] as Map)['a'];
    final http = HttpClient();
    final req = await http.postUrl(
      Uri.parse(
        'http://127.0.0.1:${BISharePort.main}${BIShareApi.upload}'
        '?sessionId=${prep['sessionId']}&fileId=a&token=$token',
      ),
    );
    req.contentLength = fa.size;
    req.add(a.readAsBytesSync());
    expect((await req.close()).statusCode, 200);
    http.close();

    await Future<void>.delayed(const Duration(seconds: 4));
    final client = TransferClient(_Identity('send-fp', 'Phone'))
      ..preferredTransport = TransportMode.tcp;
    await client.send([fa, fb], _receiver);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final names = saveDir
        .listSync(recursive: true)
        .whereType<File>()
        .map((e) => e.uri.pathSegments.last)
        .toList()
      ..sort();
    expect(names, ['IMG_0001.JPG', 'IMG_0002.JPG']);
    expect(server.isReceiving, isFalse);
  });

  test('a cancelled transfer keeps nothing for later', () async {
    if (!rust) {
      markTestSkipped('native library not built');
      return;
    }
    final src = File('${srcDir.path}/big.bin')
      ..writeAsBytesSync(List<int>.generate(2 << 20, (i) => i & 0xff));
    final f = SendableFile.fromPath(src.path, id: 'f1');
    final prep = await _rawPrepare([f]);
    await _cutUpload(prep, f, 1 << 20);
    final http = HttpClient();
    final req = await http.postUrl(
      Uri.parse(
        'http://127.0.0.1:${BISharePort.main}${BIShareApi.cancel}'
        '?sessionId=${prep['sessionId']}',
      ),
    );
    await (await req.close()).drain<void>();
    http.close();
    expect(
      saveDir.listSync().where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
    final again = await _rawPrepare([f]);
    expect(again['resumeFrom'], isEmpty);
  });

  test('a Live Photo pair arrives as a pair', () async {
    if (!rust) {
      markTestSkipped('native library not built');
      return;
    }
    final heic = File('${srcDir.path}/IMG_4821.HEIC')
      ..writeAsBytesSync(List<int>.generate(30000, (i) => i & 0xff));
    final mov = File('${srcDir.path}/IMG_4821.MOV')
      ..writeAsBytesSync(List<int>.generate(50000, (i) => (i * 5) & 0xff));
    final got = <ReceivedFile>[];
    final sub = server.received.listen(got.add);
    final client = TransferClient(_Identity('send-fp', 'Phone'))
      ..preferredTransport = TransportMode.tcp;
    await client.send([
      SendableFile.fromPath(heic.path, id: 'p').inLiveGroup('g1'),
      SendableFile.fromPath(mov.path, id: 'v').inLiveGroup('g1'),
    ], _receiver);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await sub.cancel();
    expect(
      {for (final r in got) r.fileName: r.liveGroup},
      {'IMG_4821.HEIC': 'g1', 'IMG_4821.MOV': 'g1'},
    );
  });
}
