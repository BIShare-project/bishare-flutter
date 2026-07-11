import 'dart:typed_data';

import 'package:bishare/features/clipboard/data/clipboard_token_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ClipboardShare share([int fill = 1]) => ClipboardShare(
        bytes: Uint8List.fromList(List.filled(16, fill)),
        mime: 'image/png',
      );

  test('token is single-use: second take returns null', () {
    final store = ClipboardTokenStore();
    final token = store.publish(share());
    final first = store.take(token);
    expect(first, isNotNull);
    expect(first!.bytes, share().bytes);
    expect(first.mime, 'image/png');
    expect(store.take(token), isNull); // consumed
  });

  test('unknown / wrong tokens return null', () {
    final store = ClipboardTokenStore();
    final token = store.publish(share());
    expect(store.take('not-a-token'), isNull);
    // Same length, one char off — the constant-time compare must still reject.
    final wrong = token.substring(0, token.length - 1) +
        (token.endsWith('0') ? '1' : '0');
    expect(store.take(wrong), isNull);
    expect(store.take(token), isNotNull); // the real one still works
  });

  test('tokens expire after the TTL', () {
    var now = DateTime(2026, 1, 1, 12, 0, 0);
    final store = ClipboardTokenStore(now: () => now);
    final token = store.publish(share());

    now = now.add(const Duration(seconds: 59));
    // Still valid just inside the 60s window… but don't consume it yet:
    // publish a second one to check pruning is time-based, not count-based.
    final token2 = store.publish(share(2));

    now = now.add(const Duration(seconds: 2)); // token now 61s old
    expect(store.take(token), isNull); // expired
    expect(store.take(token2), isNotNull); // 2s old — fine
  });

  test('each publish mints a distinct token (per-peer one-shots)', () {
    final store = ClipboardTokenStore();
    final a = store.publish(share());
    final b = store.publish(share());
    expect(a, isNot(b));
    expect(store.take(a), isNotNull);
    expect(store.take(b), isNotNull); // b unaffected by a's consumption
  });

  test('clear() drops everything staged', () {
    final store = ClipboardTokenStore();
    final token = store.publish(share());
    store.clear();
    expect(store.take(token), isNull);
  });
}
