import 'package:bishare/core/constants/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BISharePort', () {
    test('clipboard has its own port (58321), never shared with QUIC', () {
      // Regression guard for the CRITICAL bind failure: the Dart clipboard
      // datagram socket used to reuse the always-on Rust QUIC port (58318) and
      // could never bind. It MUST stay on its own port.
      expect(BISharePort.clipboard, 58321);
      expect(BISharePort.clipboard, isNot(BISharePort.quic));
    });

    test('every service port is distinct', () {
      final ports = <int>[
        BISharePort.main,
        BISharePort.quic,
        BISharePort.room,
        BISharePort.webdav,
        BISharePort.clipboard,
      ];
      expect(ports.toSet().length, ports.length, reason: 'ports must be unique');
    });
  });
}
