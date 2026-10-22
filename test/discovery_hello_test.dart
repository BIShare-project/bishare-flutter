import 'dart:async';
import 'dart:io';

import 'package:bishare/core/constants/protocol.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/protocol/device_info.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';

class _Identity implements DeviceIdentity {
  @override
  String get fingerprint => 'recv-fp';
  @override
  String get alias => 'Receiver';
  @override
  String get deviceType => 'desktop';

  @override
  Future<DeviceInfo> makeDeviceInfo() async => const DeviceInfo(
    alias: 'Receiver',
    version: BIShareConfig.version,
    fingerprint: 'recv-fp',
    port: BISharePort.main,
    deviceModel: 'test',
    deviceType: 'desktop',
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// `GET /api/v1/info` with [BIShareApi.helloHeader] is how a device that came
/// back asks its peers to probe it right away (DiscoveryService.greetedBy).
/// Real TransferServer on loopback; port 58317 must be free (app not running).
void main() {
  late Directory saveDir;
  late TransferServer server;
  late List<String> hellos;
  late StreamSubscription<String> sub;

  setUpAll(() async {
    await initRustForTests();
  });

  setUp(() async {
    saveDir = await Directory.systemTemp.createTemp('bishare-hello-');
    server = TransferServer(identity: _Identity(), saveDirectory: saveDir);
    await server.start();
    hellos = [];
    sub = server.hellos.listen(hellos.add);
  });

  tearDown(() async {
    await sub.cancel();
    await server.stop();
    await saveDir.delete(recursive: true);
  });

  Future<int> getInfo({String? hello}) async {
    final client = HttpClient();
    try {
      final req = await client.get(
        '127.0.0.1',
        BISharePort.main,
        BIShareApi.info,
      );
      if (hello != null) req.headers.set(BIShareApi.helloHeader, hello);
      final res = await req.close();
      await res.drain<void>();
      // The stream event is added before the response is written; let it land.
      await Future<void>.delayed(Duration.zero);
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('a hello reports the caller\'s IPv4 address', () async {
    expect(await getInfo(hello: 'sender-fp'), BIShareStatus.ok);
    expect(hellos, ['127.0.0.1']);
  });

  test('a plain info request (older peers, keep-alive) is no hello', () async {
    expect(await getInfo(), BIShareStatus.ok);
    expect(hellos, isEmpty);
  });

  test('a hidden device answers 403 and reports nothing', () async {
    server.hidden = true;
    expect(await getInfo(hello: 'sender-fp'), BIShareStatus.forbidden);
    expect(hellos, isEmpty);
  });
}
