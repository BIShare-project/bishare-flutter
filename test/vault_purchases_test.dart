import 'package:bishare/features/vault/data/vault_purchases.dart';
import 'package:bishare/features/vault/data/vault_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7 on the app's side: the purchase must name the Drive the way the
/// server reads it, the product ids must be the server's, and the reminders
/// must fall on the dates the server named.
void main() {
  group('vault id in the purchase', () {
    test('appAccountToken is the same UUID the server computes', () {
      // bishare-api server/modules/vault/store.ts vaultUuid, same input.
      expect(vaultUuid('gtghb5lzztcv2lnacs3ldy7eni'), '34cc70f5-79cc-c55d-2da0-14b6b1e3e46a');
    });
    test('a UUID Apple accepts: 8-4-4-4-12 lowercase hex', () {
      expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$').hasMatch(vaultUuid('aaaaaaaaaaaaaaaaaaaaaaaaaa')),
        isTrue,
      );
    });
    test('not a vault id is refused', () {
      expect(() => vaultUuid('NOT-A-VAULT'), throwsArgumentError);
    });
  });

  group('products', () {
    test('the eight ids of plans.ts', () {
      expect(VaultPurchases.productIds, {
        'drive_100gb_monthly',
        'drive_100gb_yearly',
        'drive_250gb_monthly',
        'drive_250gb_yearly',
        'drive_500gb_monthly',
        'drive_500gb_yearly',
        'drive_1tb_monthly',
        'drive_1tb_yearly',
      });
      for (final size in VaultPurchases.sizes) {
        for (final yearly in [false, true]) {
          final id = VaultPurchases.productFor(size, yearly: yearly);
          expect(VaultPurchases.productIds, contains(id));
          expect(VaultPurchases.sizeOf(id), size);
          expect(VaultPurchases.isYearly(id), yearly);
        }
      }
    });
    test('sizes in decimal bytes, as the server counts', () {
      expect(VaultPurchases.sizeOf('drive_1tb_yearly'), 1000000000000);
      expect(VaultPurchases.sizeOf('drive_100gb_monthly'), 100000000000);
      expect(VaultPurchases.sizeOf('free'), 0);
    });
  });

  group('reminders', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    String date(DateTime d) => d.toIso8601String().substring(0, 10);
    List<VaultReminder> plan({
      bool ready = true,
      String state = 'active',
      String? product = 'drive_100gb_monthly',
      DateTime? ends,
      bool? renews,
      DateTime? lapse,
    }) => VaultReminders.plan(
      ready: ready,
      state: state,
      plan: product,
      planEnds: ends,
      renews: renews,
      lapseEnds: lapse,
      now: now,
      date: date,
    );

    test('nothing for a plan that renews', () {
      expect(plan(ends: now.add(const Duration(days: 20)), renews: true), isEmpty);
    });
    test('three days before a plan that will not renew ends', () {
      final ends = now.add(const Duration(days: 20));
      final r = plan(ends: ends, renews: false);
      expect(r.map((x) => x.at), [ends.subtract(const Duration(days: 3))]);
    });
    test('a week and a day before a read-only Drive is emptied', () {
      final lapse = now.add(const Duration(days: 25));
      final r = plan(state: 'lapsed', lapse: lapse);
      expect(r.map((x) => x.at), [lapse.subtract(const Duration(days: 7)), lapse.subtract(const Duration(days: 1))]);
    });
    test('only what is still ahead', () {
      final lapse = now.add(const Duration(days: 3));
      expect(plan(state: 'lapsed', lapse: lapse).map((x) => x.at), [lapse.subtract(const Duration(days: 1))]);
    });
    test('a free Drive: 30 and 7 days before 12 months without use', () {
      final r = plan(state: 'free', product: 'free');
      final deleted = now.add(const Duration(days: 365));
      expect(r.map((x) => x.at), [deleted.subtract(const Duration(days: 30)), deleted.subtract(const Duration(days: 7))]);
    });
    test('nothing before the Drive is open on this device', () {
      expect(plan(ready: false, state: 'free', product: 'free'), isEmpty);
    });
    test('ids stay apart so a new schedule replaces the old', () {
      final all = [
        ...plan(state: 'lapsed', lapse: now.add(const Duration(days: 25))),
        ...plan(ends: now.add(const Duration(days: 20)), renews: false),
        ...plan(state: 'free', product: 'free'),
      ];
      expect(all.map((x) => x.id).toSet().length, all.length);
    });
  });
}
