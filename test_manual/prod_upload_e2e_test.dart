// MANUAL end-to-end check against PRODUCTION (api.bishare.app). Lives outside
// test/ on purpose so CI's `flutter test` never hits the live relay.
//
//   cargo build --manifest-path rust/Cargo.toml
//   flutter test test_manual/prod_upload_e2e_test.dart
//
// Uploads a small random file through the app's real Remote Share code path,
// pulls the stored object back from the relay, and proves (a) it is a sealed
// BSE2 container and (b) it opens with the key from the link. The scratch dir
// printed at the end holds the pieces for the web-side decrypt check.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bishare/core/crypto/bse2.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:bishare/features/remote/data/cloud_transfer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test/helpers/rust_test_lib.dart';

class _FakeServer extends Mock implements TransferServer {}

class _FakeHistory extends Mock implements HistoryRepository {}

void main() {
  test('PROD: app Remote Share upload is sealed and opens with the link key', () async {
    expect(await initRustForTests(), isTrue, reason: 'build the native lib first');
    final out = Directory(
      Platform.environment['E2E_OUT'] ?? Directory.systemTemp.createTempSync('bishare-prod-e2e-').path,
    )..createSync(recursive: true);

    final r = Random.secure();
    final plain = List<int>.generate(300 * 1024 + 321, (_) => r.nextInt(256));
    final src = File('${out.path}/original.bin')..writeAsBytesSync(plain);

    final service = CloudTransferService(_FakeServer(), _FakeHistory());
    final result = await service.uploadTransfer(
      file: src,
      fileName: 'e2e-check.bin',
      mimeType: 'application/octet-stream',
      senderAlias: 'e2e-test',
      oneTime: false,
    );
    expect(result.encrypted, isTrue);
    stdout.writeln('link: ${result.url}');

    // Pull the stored object back exactly as a browser would.
    final dio = Dio();
    final status = await dio.get<Map<String, dynamic>>(
      'https://api.bishare.app/api/v1/transfer/status/${result.rawCode}',
    );
    stdout.writeln('status: ${jsonEncode(status.data)}');
    final ct = File('${out.path}/stored.bse2');
    await dio.download(
      'https://api.bishare.app/api/v1/transfer/download/${result.rawCode}',
      ct.path,
    );
    final bytes = await ct.readAsBytes();
    expect(bytes.sublist(0, 4), Bse2.magic, reason: 'relay must hold ciphertext');
    expect(bytes.length, Bse2.ciphertextSize(plain.length));
    expect(bytes, isNot(plain));

    final back = File('${out.path}/decrypted-by-app.bin');
    await Bse2.decryptFile(input: ct, output: back, key: Bse2.decodeKey(result.key!)!);
    expect(await back.readAsBytes(), plain);

    File('${out.path}/key.txt').writeAsStringSync(result.key!);
    File('${out.path}/url.txt').writeAsStringSync(result.url);
    stdout.writeln('E2E_OUT=${out.path}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
