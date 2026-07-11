import 'package:bishare/core/protocol/device_info.dart';
import 'package:bishare/core/protocol/peer_capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

DeviceInfo _info({
  String version = '2.4',
  bool? sync,
  bool? broadcast,
  bool? media,
  bool? resumeOffset,
  bool? clipboardBinary,
}) => DeviceInfo(
  alias: 'Peer',
  version: version,
  fingerprint: 'fp',
  port: 58317,
  supportsSync: sync,
  supportsBroadcast: broadcast,
  supportsMedia: media,
  supportsResumeOffset: resumeOffset,
  supportsClipboardBinary: clipboardBinary,
);

void main() {
  group('PeerCapabilities', () {
    test('legacy peer (no flags) has no v2.4 capabilities', () {
      final caps = PeerCapabilities.of(_info(version: '2.3'));
      expect(caps.canSync, isFalse);
      expect(caps.canBroadcast, isFalse);
      expect(caps.canMedia, isFalse);
      expect(caps.canResumeOffset, isFalse);
      expect(caps.canClipboardBinary, isFalse);
    });

    test('flag + version >= 2.4 enables exactly that capability', () {
      final caps = PeerCapabilities.of(_info(sync: true, media: true));
      expect(caps.canSync, isTrue);
      expect(caps.canMedia, isTrue);
      // Unadvertised siblings stay off.
      expect(caps.canBroadcast, isFalse);
      expect(caps.canResumeOffset, isFalse);
      expect(caps.canClipboardBinary, isFalse);
    });

    test('a flag alone never wins: version below 2.4 gates it off', () {
      final caps = PeerCapabilities.of(
        _info(
          version: '2.3',
          sync: true,
          broadcast: true,
          media: true,
          resumeOffset: true,
          clipboardBinary: true,
        ),
      );
      expect(caps.canSync, isFalse);
      expect(caps.canBroadcast, isFalse);
      expect(caps.canMedia, isFalse);
      expect(caps.canResumeOffset, isFalse);
      expect(caps.canClipboardBinary, isFalse);
    });

    test('explicit false stays off even on 2.4', () {
      final caps = PeerCapabilities.of(_info(sync: false));
      expect(caps.canSync, isFalse);
    });
  });

  group('DeviceInfo v2.4 flags on the wire', () {
    test('null flags are skipped in toJson (legacy-identical payload)', () {
      final json = _info().toJson();
      expect(json.containsKey('supportsSync'), isFalse);
      expect(json.containsKey('supportsBroadcast'), isFalse);
      expect(json.containsKey('supportsMedia'), isFalse);
      expect(json.containsKey('supportsResumeOffset'), isFalse);
      expect(json.containsKey('supportsClipboardBinary'), isFalse);
    });

    test('set flags roundtrip through JSON', () {
      final json = _info(broadcast: true, clipboardBinary: true).toJson();
      final back = DeviceInfo.fromJson(json);
      expect(back.supportsBroadcast, isTrue);
      expect(back.supportsClipboardBinary, isTrue);
      expect(back.supportsSync, isNull);
    });
  });
}
