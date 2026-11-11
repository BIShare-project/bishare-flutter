// "Every file arrives exactly as it left" (transfer-quality-plan.md, point 1):
// an iPhone photo (HEIC), a video (MOV), a photo with its GPS position in
// EXIF (JPEG) and a screenshot (PNG) go through the real server and client
// the way two phones talk, encrypted end to end over TCP, and must arrive
// with the same name, the same bytes and the same Date modified.
import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/core/constants/protocol.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/io/preserve_mtime.dart';
import 'package:bishare/core/protocol/device_info.dart';
import 'package:bishare/core/server/transfer_server.dart';
import 'package:bishare/core/server/transfer_types.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:bishare/features/send/data/transfer_client.dart';
import 'package:bishare/features/send/domain/sendable_file.dart';
import 'package:bishare/features/settings/domain/settings.dart';
import 'package:bishare/src/rust/api/crypto.dart' as rc;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers/rust_test_lib.dart';
import 'helpers/start_server.dart';

/// A device with a real X25519 key (the Rust engine the app uses), so the
/// transfer is encrypted exactly like one between two phones.
class _KeyedIdentity implements DeviceIdentity {
  _KeyedIdentity(this.fingerprint, this._alias)
    : _engine = rc.EncryptionEngine.generate();

  final rc.EncryptionEngine _engine;
  @override
  final String fingerprint;
  final String _alias;
  @override
  String get alias => _alias;
  @override
  String get deviceType => 'phone';
  @override
  String get publicKeyBase64 => _engine.publicKeyBase64();
  @override
  List<int>? deriveKey(String peerPublicKeyBase64) =>
      _engine.deriveSharedKey(peerPublicKeyBase64: peerPublicKeyBase64);

  @override
  Future<DeviceInfo> makeDeviceInfo() async => DeviceInfo(
    alias: _alias,
    version: BIShareConfig.version,
    fingerprint: fingerprint,
    port: BISharePort.main,
    deviceModel: 'test',
    deviceType: 'phone',
    publicKey: publicKeyBase64,
  );

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _fixtures = 'test/fixtures/byte_for_byte';

/// Date modified the sender's files carry (2026-03-14 09:26:53 UTC).
const _mtime = 1773480413000;

void main() {
  late bool rust;
  late Directory saveDir;
  late Directory srcDir;
  late TransferServer server;
  late _KeyedIdentity receiver;

  setUpAll(() async {
    rust = await initRustForTests();
  });

  setUp(() async {
    if (!rust) return;
    saveDir = await Directory.systemTemp.createTemp('bishare-b4b-recv-');
    srcDir = await Directory.systemTemp.createTemp('bishare-b4b-send-');
    receiver = _KeyedIdentity('recv-fp', 'Receiver');
    server = TransferServer(identity: receiver, saveDirectory: saveDir)
      ..autoAccept = AutoAcceptMode.acceptAll;
    await startServerWhenFree(server);
  });

  tearDown(() async {
    if (!rust) return;
    await server.stop();
    await saveDir.delete(recursive: true);
    await srcDir.delete(recursive: true);
  });

  test('photo, video, GPS photo and screenshot arrive byte for byte', () async {
    if (!rust) {
      markTestSkipped(rustUnavailableReason);
      return;
    }
    final names = ['photo.HEIC', 'clip.MOV', 'gps.jpg', 'shot.png'];
    final files = <SendableFile>[];
    final digests = <String, String>{};
    for (final (i, name) in names.indexed) {
      final src = File('$_fixtures/$name').copySync('${srcDir.path}/$name');
      await applyReceivedMtime(src, _mtime);
      files.add(SendableFile.fromPath(src.path, id: 'f$i'));
      digests[name] = sha256.convert(src.readAsBytesSync()).toString();
    }
    // The photo's position, so its survival below is not vacuous.
    expect(_hasGps(File('$_fixtures/gps.jpg').readAsBytesSync()), isTrue);

    final got = <ReceivedFile>[];
    final sub = server.received.listen(got.add);
    final client = TransferClient(_KeyedIdentity('send-fp', 'Sender'))
      ..preferredTransport = TransportMode.tcp;
    await client.send(
      files,
      DiscoveredDevice(
        fingerprint: 'recv-fp',
        alias: 'Receiver',
        host: '127.0.0.1',
        port: BISharePort.main,
        lastSeen: DateTime.now(),
        firstSeen: DateTime.now(),
        version: BIShareConfig.version,
        publicKey: receiver.publicKeyBase64,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await sub.cancel();

    expect(got.map((r) => r.fileName).toSet(), names.toSet());
    for (final r in got) {
      expect(r.encrypted, isTrue, reason: '${r.fileName} must travel E2E');
      final saved = File(r.savedPath);
      final bytes = saved.readAsBytesSync();
      expect(
        sha256.convert(bytes).toString(),
        digests[r.fileName],
        reason: '${r.fileName} changed on the way',
      );
      expect(
        saved.lastModifiedSync().millisecondsSinceEpoch ~/ 1000,
        _mtime ~/ 1000,
        reason: '${r.fileName} lost its Date modified',
      );
      if (r.fileName == 'gps.jpg') expect(_hasGps(bytes), isTrue);
    }
  });
}

bool _hasGps(Uint8List jpg) {
  final exif = img.decodeJpgExif(jpg);
  return exif != null && !exif.gpsIfd.isEmpty;
}
