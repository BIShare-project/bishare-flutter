import 'package:bishare/features/clipboard/data/clipboard_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the clipboard receiver will even look at.
///
/// Every datagram is sealed to one peer, so an unsealed one has no business
/// being acted on — accepting plaintext "for older peers" would be a downgrade
/// anyone on the network could ask for.
void main() {
  const own = 'me-fingerprint';
  const boxOf = ClipboardService.sealedBoxOf;

  Map<String, dynamic> envelope({
    String type = 'clipboard',
    Object? sender = 'peer-fingerprint',
    Object? box = 'c2VhbGVk',
  }) {
    final m = <String, dynamic>{'type': type, 'v': 2};
    if (sender != null) m['sender'] = sender;
    if (box != null) m['box'] = box;
    return m;
  }

  test('a sealed datagram from another peer yields its box', () {
    expect(boxOf(envelope(), own), 'c2VhbGVk');
  });

  test('an unsealed datagram is refused', () {
    // The pre-encryption wire shape: text in the clear, no box at all.
    expect(boxOf({'type': 'clipboard', 'sender': 'peer', 'text': 'hello'}, own), isNull);
    expect(boxOf(envelope(box: null), own), isNull);
    expect(boxOf(envelope(box: ''), own), isNull);
  });

  test('our own datagram looped back is ignored', () {
    expect(boxOf(envelope(sender: own), own), isNull);
  });

  test('another message type is ignored', () {
    expect(boxOf(envelope(type: 'transfer'), own), isNull);
  });

  test('a missing or non-string sender is refused', () {
    expect(boxOf(envelope(sender: null), own), isNull);
    expect(boxOf(envelope(sender: ''), own), isNull);
    expect(boxOf(envelope(sender: 42), own), isNull);
  });

  test('a non-string box is refused', () {
    expect(boxOf(envelope(box: 7), own), isNull);
    expect(boxOf(envelope(box: const ['a']), own), isNull);
  });
}
