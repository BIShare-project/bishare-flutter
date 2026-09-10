import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:dio/dio.dart';
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

  // ── multipart ──
  static const int partSize = 1024 * 1024; // small so tests stay small
  Map<String, dynamic>? mpInitBody;
  Map<String, dynamic>? mpCompleteBody;
  Map<String, dynamic>? mpAbortBody;
  final Map<int, Uint8List> parts = {};
  final List<int> refreshedParts = [];
  final List<int> partPutAttempts = [];

  /// Part whose FIRST PUT is answered 403, as an expired presign would be.
  int? failFirstPutOfPart;

  /// Part whose EVERY PUT is answered 403 — a presign that never recovers.
  int? alwaysFailPart;

  /// Part whose PUT is held open (body read, no response) until [release]
  /// completes — lets a test cancel while a part is genuinely in flight.
  int? holdPart;
  final Completer<void> held = Completer<void>();
  final Completer<void> release = Completer<void>();

  String get base => 'http://${server.address.address}:${server.port}';

  static Future<_Relay> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _Relay(s);
    s.listen(relay._handle);
    return relay;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      await _route(req);
      await req.response.close();
    } on Object {
      // The client may drop the connection mid-request (a cancel test does
      // exactly that); a dead socket must not fail the test as an unhandled
      // error from the server side.
    }
  }

  Future<void> _route(HttpRequest req) async {
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
    } else if (req.method == 'POST' &&
        req.uri.path == '/api/v1/transfer/multipart/init') {
      mpInitBody =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      final size = (mpInitBody!['size'] as num).toInt();
      final total = max(1, (size + partSize - 1) ~/ partSize);
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'uploadId': 'upload-1',
            'storageKey': 'transfers/abc/holiday.mp4',
            'partSize': partSize,
            'totalParts': total,
            'uploadExpiresIn': 7200,
            'parts': [
              for (var p = 1; p <= total; p++)
                {'part_number': p, 'upload_url': '$base/r2/part?n=$p'},
            ],
          }),
        );
    } else if (req.method == 'POST' &&
        req.uri.path == '/api/v1/transfer/multipart/part-urls') {
      final body =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      final nums = (body['partNumbers'] as List).cast<int>();
      refreshedParts.addAll(nums);
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'parts': [
              for (final p in nums)
                {'part_number': p, 'upload_url': '$base/r2/part?n=$p'},
            ],
          }),
        );
    } else if (req.method == 'PUT' && req.uri.path == '/r2/part') {
      final n = int.parse(req.uri.queryParameters['n']!);
      partPutAttempts.add(n);
      final chunks = <int>[];
      await for (final c in req) {
        chunks.addAll(c);
      }
      final firstAttempt = partPutAttempts.where((x) => x == n).length == 1;
      if (holdPart == n) {
        if (!held.isCompleted) held.complete();
        await release.future;
      }
      if (alwaysFailPart == n || (failFirstPutOfPart == n && firstAttempt)) {
        req.response.statusCode = 403; // expired presign
      } else {
        parts[n] = Uint8List.fromList(chunks);
        req.response.statusCode = 200;
      }
    } else if (req.method == 'POST' &&
        req.uri.path == '/api/v1/transfer/multipart/abort') {
      mpAbortBody =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': true}));
    } else if (req.method == 'POST' &&
        req.uri.path == '/api/v1/transfer/multipart/complete') {
      mpCompleteBody =
          jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
      final ordered = parts.keys.toList()..sort();
      putBody = Uint8List.fromList([for (final k in ordered) ...parts[k]!]);
      req.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'code': 'MPX-YZW',
            'rawCode': 'MPXYZW',
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
  }

  Future<void> close() async {
    if (!release.isCompleted) release.complete();
    await server.close(force: true);
  }
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

  group('multipart (bodies above the threshold)', () {
    late CloudTransferService mp;

    setUp(() {
      mp = CloudTransferService(
        _FakeServer(),
        _FakeHistory(),
        apiBase: relay.base,
        multipartThreshold: _Relay.partSize, // anything bigger than one part
      );
    });

    test(
      'a sealed body goes up in parts and completes with the ciphertext size',
      () async {
        if (!rust) return markTestSkipped(rustUnavailableReason);
        final file = await plainFile(
          _Relay.partSize * 2 + 777,
        ); // → 3 parts sealed
        final plain = await file.readAsBytes();
        final progress = <int>[];

        final result = await mp.uploadTransfer(
          file: file,
          fileName: 'holiday.mp4',
          mimeType: 'video/mp4',
          senderAlias: 'Nima',
          onProgress: (sent, total) => progress.add(sent),
        );

        final ctSize = Bse2.ciphertextSize(plain.length);
        expect(
          relay.mpInitBody!['size'],
          ctSize,
          reason: 'reserved by ciphertext size',
        );
        expect(relay.mpInitBody!['name'], 'holiday.mp4');
        expect(relay.parts.keys.toList()..sort(), [1, 2, 3]);
        expect(relay.parts[1]!.length, _Relay.partSize);
        expect(
          relay.parts[3]!.length,
          ctSize - 2 * _Relay.partSize,
          reason: 'last part = remainder',
        );
        expect(relay.putBody!.length, ctSize);
        expect(relay.putBody!.sublist(0, 4), Bse2.magic);
        expect(relay.mpCompleteBody!['size'], ctSize);
        expect(relay.mpCompleteBody!['sender_alias'], 'Nima');
        expect(relay.mpCompleteBody!['one_time'], isTrue);
        expect(
          relay.createBody,
          isNull,
          reason: 'single-PUT flow must not be touched',
        );
        expect(relay.refreshedParts, isEmpty, reason: 'init URLs were enough');
        expect(relay.mpAbortBody, isNull, reason: 'a finished upload is kept');

        // Progress is monotonic and lands exactly on the ciphertext total.
        for (var i = 1; i < progress.length; i++) {
          expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
        }
        expect(progress.last, ctSize);

        // The parts reassemble into a container that opens with the link key.
        final sealed = File('${tmp.path}/sealed.bse2')
          ..writeAsBytesSync(relay.putBody!);
        final out = File('${tmp.path}/out.mp4');
        await Bse2.decryptFile(
          input: sealed,
          output: out,
          key: Bse2.decodeKey(result.key!)!,
        );
        expect(await out.readAsBytes(), plain);
        expect(
          result.url,
          'https://bishare.app/transfer/MPXYZW#k=${result.key}',
        );
      },
    );

    test('an expired part URL is re-presigned and the part retried', () async {
      final file = await plainFile(_Relay.partSize * 2 + 5);
      final plain = await file.readAsBytes();
      relay.failFirstPutOfPart = 2;

      await mp.uploadTransfer(
        file: file,
        fileName: 'holiday.mp4',
        mimeType: 'video/mp4',
        senderAlias: 'Nima',
        encrypt: false,
      );

      expect(relay.partPutAttempts, [
        1,
        2,
        2,
        3,
      ], reason: 'part 2 failed once, then succeeded');
      expect(relay.refreshedParts, [
        2,
      ], reason: 'only the failed part asked for a fresh URL');
      expect(
        relay.putBody,
        plain,
        reason: 'the retried slice was re-read from disk intact',
      );
    });

    test(
      'a part that never succeeds fails the upload after the retry budget',
      () async {
        final file = await plainFile(_Relay.partSize + 1);
        relay.alwaysFailPart = 2;

        await expectLater(
          mp.uploadTransfer(
            file: file,
            fileName: 'holiday.mp4',
            mimeType: 'video/mp4',
            senderAlias: 'Nima',
            encrypt: false,
          ),
          throwsA(isA<DioException>()),
        );

        // 1 initial + 3 retries, each retry with a fresh URL; never completed.
        expect(relay.partPutAttempts.where((p) => p == 2).length, 4);
        expect(relay.refreshedParts, [2, 2, 2]);
        expect(relay.mpCompleteBody, isNull);
        // …and the parts already on R2 are freed, not left for the 24 h sweep.
        expect(relay.mpAbortBody, {
          'uploadId': 'upload-1',
          'storageKey': 'transfers/abc/holiday.mp4',
        });
      },
    );

    test('cancelling mid-upload aborts the multipart on the server', () async {
      final file = await plainFile(_Relay.partSize * 2 + 5);
      relay.holdPart = 2; // part 1 lands, part 2 is in flight when we cancel
      final cancel = CancelToken();

      final upload = mp.uploadTransfer(
        file: file,
        fileName: 'holiday.mp4',
        mimeType: 'video/mp4',
        senderAlias: 'Nima',
        encrypt: false,
        cancel: cancel,
      );
      await relay.held.future;
      cancel.cancel();

      await expectLater(
        upload,
        throwsA(
          isA<DioException>().having(
            (e) => CancelToken.isCancel(e),
            'cancelled',
            isTrue,
          ),
        ),
      );
      expect(relay.parts.keys, [1], reason: 'only part 1 had completed');
      expect(relay.mpCompleteBody, isNull);
      expect(relay.mpAbortBody, {
        'uploadId': 'upload-1',
        'storageKey': 'transfers/abc/holiday.mp4',
      }, reason: 'the cancel reached the server as an abort');
    });
  });

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
