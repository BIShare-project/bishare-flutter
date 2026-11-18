import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_api.dart';
import 'package:bishare/features/vault/data/vault_backup_notice.dart';
import 'package:bishare/features/vault/data/vault_purchases.dart';
import 'package:bishare/features/vault/presentation/drive/drive_backup_offer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:mocktail/mocktail.dart';

class _Store extends Mock implements InAppPurchase {}

class _Api extends Mock implements VaultApi {}

class _Account extends Mock implements VaultAccount {}

PricingPhaseWrapper _phase(int micros, String period, {int cycles = 0}) =>
    PricingPhaseWrapper(
      billingCycleCount: cycles,
      billingPeriod: period,
      formattedPrice: micros == 0 ? 'Free' : r'$2.49',
      priceAmountMicros: micros,
      priceCurrencyCode: 'USD',
      recurrenceMode: micros == 0
          ? RecurrenceMode.finiteRecurring
          : RecurrenceMode.infiniteRecurring,
    );

/// Google Play's answer for one subscription: its base plan and [offers].
List<GooglePlayProductDetails> _play(
  String id, {
  List<SubscriptionOfferDetailsWrapper> offers = const [],
}) => GooglePlayProductDetails.fromProductDetails(
  ProductDetailsWrapper(
    description: '',
    name: id,
    productId: id,
    productType: ProductType.subs,
    title: id,
    subscriptionOfferDetails: [
      ...offers,
      SubscriptionOfferDetailsWrapper(
        basePlanId: 'monthly',
        offerTags: const [],
        offerIdToken: 'base-$id',
        pricingPhases: [_phase(2490000, 'P1M')],
      ),
    ],
  ),
);

SubscriptionOfferDetailsWrapper _offer(
  String token,
  List<PricingPhaseWrapper> phases,
) => SubscriptionOfferDetailsWrapper(
  basePlanId: 'monthly',
  offerId: token,
  offerTags: const [],
  offerIdToken: token,
  pricingPhases: phases,
);

/// A free trial on a Drive plan (owner 2026-11-17): what the stores list has
/// to come out as one price per plan and the trial apart, and the trial is
/// promised only to someone the store says may take it.
void main() {
  group('a period in days', () {
    test('the periods the stores write', () {
      expect(VaultPurchases.periodDays('P1W'), 7);
      expect(VaultPurchases.periodDays('P7D'), 7);
      expect(VaultPurchases.periodDays('P3D'), 3);
      expect(VaultPurchases.periodDays('P2W'), 14);
      expect(VaultPurchases.periodDays('P1M'), 30);
      expect(VaultPurchases.periodDays('P1Y'), 365);
      expect(VaultPurchases.periodDays('P1W3D'), 10);
    });
    test('anything else is no period', () {
      expect(VaultPurchases.periodDays(''), 0);
      expect(VaultPurchases.periodDays('7 days'), 0);
      expect(VaultPurchases.periodDays('PT1H'), 0);
    });
  });

  group('what Google Play lists', () {
    test('a plan with no offer is the plan', () {
      final listed = VaultPurchases.sortListed(_play('drive_100gb_monthly'));
      expect(listed.plans.keys, ['drive_100gb_monthly']);
      expect(listed.plans['drive_100gb_monthly']!.price, r'$2.49');
      expect(listed.trialDays, isEmpty);
    });

    test('a free trial does not take the place of the price', () {
      final listed = VaultPurchases.sortListed(
        _play(
          'drive_100gb_monthly',
          offers: [
            _offer('trial', [
              _phase(0, 'P1W', cycles: 1),
              _phase(2490000, 'P1M'),
            ]),
          ],
        ),
      );
      // Whatever the order Play listed them in.
      expect(listed.plans['drive_100gb_monthly']!.price, r'$2.49');
      expect(listed.trialDays, {'drive_100gb_monthly': 7});
      final trial =
          listed.trialOffers['drive_100gb_monthly']! as GooglePlayProductDetails;
      expect(trial.offerToken, 'trial');
    });

    test('an offer that is not a free trial is left out', () {
      final listed = VaultPurchases.sortListed(
        _play(
          'drive_100gb_monthly',
          offers: [
            _offer('half', [
              _phase(1240000, 'P1M', cycles: 3),
              _phase(2490000, 'P1M'),
            ]),
          ],
        ),
      );
      expect(listed.plans['drive_100gb_monthly']!.price, r'$2.49');
      expect(listed.trialDays, isEmpty);
      expect(listed.trialOffers, isEmpty);
    });

    test('a trial of several periods counts them all', () {
      final listed = VaultPurchases.sortListed(
        _play(
          'drive_100gb_monthly',
          offers: [
            _offer('trial', [
              _phase(0, 'P1W', cycles: 2),
              _phase(2490000, 'P1M'),
            ]),
          ],
        ),
      );
      expect(listed.trialDays, {'drive_100gb_monthly': 14});
    });
  });

  group('the App Store trial', () {
    late _Store store;
    late List<String> asked;

    ProductDetails product(String id) => ProductDetails(
      id: id,
      title: id,
      description: '',
      price: r'$2.49',
      rawPrice: 2.49,
      currencyCode: 'USD',
    );

    VaultPurchases make({
      ({int days, Set<String> products})? stated,
      bool eligible = true,
      bool fails = false,
    }) => VaultPurchases(
      account: _Account(),
      api: _Api(),
      store: store,
      appleTrial: () => stated,
      appleTrialEligible: (id) async {
        asked.add(id);
        if (fails) throw StateError('no StoreKit 2');
        return eligible;
      },
    );

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      store = _Store();
      asked = [];
      when(() => store.isAvailable()).thenAnswer((_) async => true);
      when(() => store.queryProductDetails(any())).thenAnswer(
        (_) async => ProductDetailsResponse(
          productDetails: [
            product('drive_100gb_monthly'),
            product('drive_250gb_monthly'),
          ],
          notFoundIDs: const [],
        ),
      );
    });

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    const stated = (
      days: 7,
      products: {'drive_100gb_monthly', 'drive_100gb_yearly'},
    );

    test('stated by the server and allowed by StoreKit: offered', () async {
      final purchases = make(stated: stated);
      await purchases.load();
      expect(purchases.trials, {'drive_100gb_monthly': 7});
      expect(purchases.trialDays('drive_100gb_monthly'), 7);
      expect(purchases.trialDays('drive_250gb_monthly'), isNull);
      // A product not on sale here is not asked about.
      expect(asked, ['drive_100gb_monthly']);
    });

    test('someone who had an introductory offer gets none', () async {
      final purchases = make(stated: stated, eligible: false);
      await purchases.load();
      expect(purchases.trials, isEmpty);
    });

    test('nothing stated: nothing promised, StoreKit not asked', () async {
      final purchases = make();
      await purchases.load();
      expect(purchases.trials, isEmpty);
      expect(asked, isEmpty);
    });

    test('StoreKit cannot say: nothing promised', () async {
      final purchases = make(stated: stated, fails: true);
      await purchases.load();
      expect(purchases.trials, isEmpty);
      expect(purchases.products, hasLength(2));
    });
  });

  group('the offer to back up photos', () {
    bool due({
      bool ready = true,
      bool library = true,
      bool on = false,
      bool offered = false,
    }) => DriveBackupOffer.due(
      ready: ready,
      library: library,
      on: on,
      offered: offered,
    );

    test('made once, to a ready Drive on a phone with backup off', () {
      expect(due(), isTrue);
      expect(due(offered: true), isFalse);
      expect(due(on: true), isFalse);
      expect(due(library: false), isFalse);
      expect(due(ready: false), isFalse);
    });
  });

  group('the full-Drive notification', () {
    final now = DateTime(2026, 11, 17, 12);
    test('the first time, and again after a week', () {
      expect(VaultBackupNotice.due(lastAtMs: null, now: now), isTrue);
      expect(
        VaultBackupNotice.due(
          lastAtMs: now
              .subtract(const Duration(days: 6))
              .millisecondsSinceEpoch,
          now: now,
        ),
        isFalse,
      );
      expect(
        VaultBackupNotice.due(
          lastAtMs: now
              .subtract(const Duration(days: 7))
              .millisecondsSinceEpoch,
          now: now,
        ),
        isTrue,
      );
    });
    test('a clock set back does not silence it for good', () {
      expect(
        VaultBackupNotice.due(
          lastAtMs: now.add(const Duration(days: 400)).millisecondsSinceEpoch,
          now: now,
        ),
        isTrue,
      );
    });
  });
}
