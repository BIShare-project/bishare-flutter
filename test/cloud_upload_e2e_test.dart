import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/remote/data/cloud_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/rust_test_lib.dart';

class _FakeServer extends Mock implements TransferServer {}

class _FakeHistory extends Mock implements HistoryRepository {}

/// A stand-in for api.bishare.app + R2: answers the presigned `upload-url`
/// handshake and captures exactly the bytes the app PUTs — so the assertion
/// is on what actually leaves the device, not on what the code intends.
class _Relay {
  _Relay(this.server);
  final HttpServer server;
  Map<String, dynamic>? createBody;
  Uint8List? putBody;
  String? putContentType;
  int? putContentLength;

  String get base => 'http://${server.address.address}:${server.port}';

  static Future<_Relay> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _Relay(s);
    s.listen(relay._handle);
    return relay;
  }

  Future<void> _handle(HttpRequest req) async {
    if (req.method == 'POST' && req.uri.path == '/api/v1/transfer/upload-url') {
      createBody =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'uploadUrl': '$base/r2/object',
            'uploadHeaders': {'Content-Type': createBody!['mime_type']},
            'code': 'ABC-DEF',
            'rawCode': 'ABCDEF',
            'deleteToken': 'tok',
            'expiresAt': DateTime.now()
                .add(const Duration(hours: 24))
                .toIso8601String(),
          }),
        );
    } else if (req.method == 'PUT' && req.uri.path == '/r2/object') {
      final chunks = <int>[];
      await for (final c in req) {
        chunks.addAll(c);
      }
      putBody = Uint8List.fromList(chunks);
      putContentType = req.headers.contentType?.mimeType;
      putContentLength = req.contentLength;
      req.response.statusCode = 200;
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  late bool rust;
  late Directory tmp;
  late _Relay relay;
  late CloudTransferService service;

  setUpAll(() async {
    rust = await initRustForTests();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cloud-upload-test');
    relay = await _Relay.start();
    service = CloudTransferService(
      _FakeServer(),
      _FakeHistory(),
      apiBase: relay.base,
    );
  });

  tearDown(() async {
    await relay.close();
    await tmp.delete(recursive: true);
  });

  Future<File> plainFile(int size) async {
    final r = Random(11);
    final f = File('${tmp.path}/holiday.mp4');
    await f.writeAsBytes(
      List.generate(size, (_) => r.nextInt(256)),
      flush: true,
    );
    return f;
  }

  test(
    'Remote Share uploads ONLY ciphertext, and the key lives in the link',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final file = await plainFile(Bse2.recordSize + 777);
      final plain = await file.readAsBytes();
      final encProgress = <int>[];
      final upProgress = <int>[];

      final result = await service.uploadTransfer(
        file: file,
        fileName: 'holiday.mp4',
        mimeType: 'video/mp4',
        senderAlias: 'Nima',
        onEncryptProgress: (done, total) => encProgress.add(done),
        onProgress: (sent, total) => upProgress.add(sent),
      );

      // What left the device is a sealed container, never the file.
      final body = relay.putBody!;
      expect(body.sublist(0, 4), Bse2.magic);
      expect(body, isNot(plain));
      expect(body.length, Bse2.ciphertextSize(plain.length));
      expect(relay.putContentLength, body.length);
      expect(
        relay.putContentType,
        'video/mp4',
        reason: 'mime is metadata, not payload',
      );

      // The server was told the CIPHERTEXT size — that is what it stores.
      expect(relay.createBody!['size'], body.length);
      expect(relay.createBody!['name'], 'holiday.mp4');
      expect(relay.createBody!['mime_type'], 'video/mp4');
      expect(
        jsonEncode(relay.createBody),
        isNot(contains(result.key)),
        reason: 'the key must never be sent to the server',
      );

      // The link carries the key after #, and only the link can open it.
      expect(result.encrypted, isTrue);
      expect(result.key, hasLength(43));
      expect(result.url, 'https://bishare.app/transfer/ABCDEF#k=${result.key}');
      expect(result.code, 'ABC-DEF');

      final sealed = File('${tmp.path}/sealed.bse2')..writeAsBytesSync(body);
      final out = File('${tmp.path}/out.mp4');
      await Bse2.decryptFile(
        input: sealed,
        output: out,
        key: Bse2.decodeKey(result.key!)!,
      );
      expect(await out.readAsBytes(), plain);

      expect(encProgress.last, plain.length);
      expect(upProgress.last, body.length);

      // The scratch ciphertext did not outlive the upload.
      final leftovers = Directory.systemTemp.listSync().where(
        (e) => e.path.contains('bishare-e2e-'),
      );
      expect(leftovers, isEmpty);
    },
  );

  test(
    'with encryption off the file is uploaded as-is and the link has no key',
    () async {
      final file = await plainFile(5000);
      final plain = await file.readAsBytes();

      final result = await service.uploadTransfer(
        file: file,
        fileName: 'holiday.mp4',
        mimeType: 'video/mp4',
        senderAlias: 'Nima',
        encrypt: false,
      );

      expect(relay.putBody, plain);
      expect(relay.createBody!['size'], plain.length);
      expect(result.encrypted, isFalse);
      expect(result.url, 'https://bishare.app/transfer/ABCDEF');
    },
  );

  test('an empty file is still sealed (one authenticated tag)', () async {
    if (!rust) return markTestSkipped(rustUnavailableReason);
    final file = await plainFile(0);
    final result = await service.uploadTransfer(
      file: file,
      fileName: 'empty.txt',
      mimeType: 'text/plain',
      senderAlias: 'Nima',
    );
    expect(relay.putBody!.length, 40);
    expect(
      relay.createBody!['size'],
      40,
      reason: 'server rejects size <= 0; a sealed empty file is 40 bytes',
    );
    expect(result.encrypted, isTrue);
  });
}
