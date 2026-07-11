import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:flutter_test/flutter_test.dart';

DiscoveredDevice _dev(
  String fingerprint, {
  required DateTime firstSeen,
  DateTime? lastSeen,
}) => DiscoveredDevice(
  fingerprint: fingerprint,
  alias: fingerprint,
  host: '192.168.1.1',
  port: 8080,
  lastSeen: lastSeen ?? firstSeen,
  firstSeen: firstSeen,
);

void main() {
  group('stableDeviceOrder', () {
    test('orders by firstSeen ascending (new devices append at the bottom)', () {
      final a = _dev('a', firstSeen: DateTime(2026, 1, 1, 10, 0, 0));
      final b = _dev('b', firstSeen: DateTime(2026, 1, 1, 10, 0, 5));
      final c = _dev('c', firstSeen: DateTime(2026, 1, 1, 10, 0, 9));

      // Input in a jumbled order — output must be first-seen order.
      final ordered = stableDeviceOrder([c, a, b]);
      expect(ordered.map((d) => d.fingerprint), ['a', 'b', 'c']);
    });

    test(
      'is churn-proof: any input permutation yields the same order',
      () {
        final a = _dev('a', firstSeen: DateTime(2026, 1, 1, 10, 0, 0));
        final b = _dev('b', firstSeen: DateTime(2026, 1, 1, 10, 0, 5));
        final c = _dev('c', firstSeen: DateTime(2026, 1, 1, 10, 0, 9));

        const expected = ['a', 'b', 'c'];
        for (final input in [
          [a, b, c],
          [c, b, a],
          [b, c, a], // e.g. keep-alive moved `a` to the end of the map
          [a, c, b],
        ]) {
          expect(
            stableDeviceOrder(input).map((d) => d.fingerprint),
            expected,
            reason: 'order must not depend on discovery/map insertion order',
          );
        }
      },
    );

    test('a device keeps its slot even as its lastSeen keeps refreshing', () {
      final a = _dev('a', firstSeen: DateTime(2026, 1, 1, 10, 0, 0));
      final b = _dev('b', firstSeen: DateTime(2026, 1, 1, 10, 0, 5));

      final before = stableDeviceOrder([a, b]).map((d) => d.fingerprint).toList();

      // Simulate a keep-alive tick: `a` gets a fresh lastSeen and is re-inserted
      // last in the map. firstSeen is untouched, so its slot must not change.
      final aRefreshed = a.copyWith(lastSeen: DateTime(2026, 1, 1, 10, 5, 0));
      final after = stableDeviceOrder([b, aRefreshed]).map((d) => d.fingerprint);

      expect(after, before); // ['a', 'b'] both times — no jump
    });

    test('equal firstSeen falls back to fingerprint for a total order', () {
      final t = DateTime(2026, 1, 1, 10, 0, 0);
      final x = _dev('x', firstSeen: t);
      final m = _dev('m', firstSeen: t);
      final f = _dev('f', firstSeen: t);

      // Same instant (e.g. a probeSubnet batch) — fingerprint breaks the tie
      // deterministically regardless of input order.
      expect(stableDeviceOrder([x, m, f]).map((d) => d.fingerprint), [
        'f',
        'm',
        'x',
      ]);
      expect(stableDeviceOrder([f, x, m]).map((d) => d.fingerprint), [
        'f',
        'm',
        'x',
      ]);
    });

    test('adding a newer device never moves the existing ones', () {
      final a = _dev('a', firstSeen: DateTime(2026, 1, 1, 10, 0, 0));
      final b = _dev('b', firstSeen: DateTime(2026, 1, 1, 10, 0, 5));
      final newcomer = _dev('z', firstSeen: DateTime(2026, 1, 1, 10, 1, 0));

      final ordered = stableDeviceOrder([b, newcomer, a]);
      // Existing pair keeps its relative order; newcomer lands at the end.
      expect(ordered.map((d) => d.fingerprint), ['a', 'b', 'z']);
    });
  });
}
