import 'package:bishare/features/clipboard/data/clipboard_service.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who is allowed to put text on this device's clipboard.
///
/// Before this rule existed, any host that could reach the clipboard port
/// could set the clipboard: the receive path checked only that the datagram
/// did not come from us. Text is the payload, so that is a swapped account
/// number or wallet address landing in a paste, not merely being read.
void main() {
  DiscoveredDevice peer({
    String fingerprint = 'aa11',
    String host = '192.168.1.20',
    String alias = 'Laptop',
  }) =>
      DiscoveredDevice(
        fingerprint: fingerprint,
        alias: alias,
        host: host,
        port: 58317,
        lastSeen: DateTime(2026, 9, 18),
        firstSeen: DateTime(2026, 9, 18),
      );

  const allow = ClipboardService.allowedTextSender;

  test('a discovered peer sending from its own address is accepted', () {
    final p = peer();
    expect(allow([p], 'aa11', '192.168.1.20'), same(p));
  });

  test('an unknown fingerprint is refused', () {
    expect(allow([peer()], 'ffff', '192.168.1.20'), isNull);
  });

  test('no peers discovered at all: nothing is accepted', () {
    expect(allow(const [], 'aa11', '192.168.1.20'), isNull);
  });

  test('a known fingerprint from a different address is refused', () {
    // Discovery broadcasts fingerprints in the clear, so knowing one must not
    // be enough to impersonate its owner from somewhere else on the network.
    expect(allow([peer()], 'aa11', '192.168.1.99'), isNull);
  });

  test('a missing or empty sender is refused', () {
    expect(allow([peer()], null, '192.168.1.20'), isNull);
    expect(allow([peer()], '', '192.168.1.20'), isNull);
  });

  test('the right peer is picked out of several', () {
    final a = peer(fingerprint: 'aa11', host: '192.168.1.20', alias: 'Laptop');
    final b = peer(fingerprint: 'bb22', host: '192.168.1.21', alias: 'Phone');
    expect(allow([a, b], 'bb22', '192.168.1.21'), same(b));
    // …and a cross-matched pair is still refused.
    expect(allow([a, b], 'bb22', '192.168.1.20'), isNull);
  });
}
