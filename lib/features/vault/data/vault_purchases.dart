import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'vault_account.dart';
import 'vault_api.dart';

/// Drive plans bought through the App Store or Google Play (drive-plan.md
/// phase 7). The store takes the money; the server decides what it buys:
/// every purchase or restore is handed to `POST entitlement`, which checks it
/// with the store and answers the plan. Nothing is unlocked on this device on
/// the store's word alone.
///
/// The purchase names the Drive it is for: on Apple the vault id's 16 bytes as
/// a UUID (appAccountToken), on Google the vault id itself
/// (obfuscatedExternalAccountId). Windows and Linux have no store here; they
/// join a Drive bought on a phone or a Mac.
class VaultPurchases extends ChangeNotifier {
  VaultPurchases({
    required VaultAccount account,
    required VaultApi api,
    InAppPurchase? store,
  }) : _account = account,
       _api = api,
       _storeOverride = store;

  /// The eight products (bishare-api server/modules/vault/plans.ts).
  static const productIds = <String>{
    'drive_100gb_monthly',
    'drive_100gb_yearly',
    'drive_250gb_monthly',
    'drive_250gb_yearly',
    'drive_500gb_monthly',
    'drive_500gb_yearly',
    'drive_1tb_monthly',
    'drive_1tb_yearly',
  };

  static const _gb = 1000000000;

  /// The sizes on sale, smallest first, in decimal bytes as the server counts.
  static const sizes = <int>[100 * _gb, 250 * _gb, 500 * _gb, 1000 * _gb];

  static String productFor(int size, {required bool yearly}) {
    final name = size >= 1000 * _gb ? '1tb' : '${size ~/ _gb}gb';
    return 'drive_${name}_${yearly ? 'yearly' : 'monthly'}';
  }

  static int sizeOf(String productId) {
    final m = RegExp(r'^drive_(\d+)(gb|tb)_').firstMatch(productId);
    if (m == null) return 0;
    return int.parse(m[1]!) * (m[2] == 'tb' ? 1000 : 1) * _gb;
  }

  static bool isYearly(String productId) => productId.endsWith('_yearly');

  /// Phones, tablets and Macs can buy here. (defaultTargetPlatform is the
  /// platform the app runs on; the store screenshots override it.)
  static bool get supported =>
      !kIsWeb &&
      const {
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  static bool get _android => defaultTargetPlatform == TargetPlatform.android;

  /// The store this device buys through, as the server names it.
  static String get storeHere => _android ? 'google' : 'apple';

  /// Where a subscription is changed or cancelled.
  static Uri manageUri(String? productId) => _android
      ? Uri.https('play.google.com', '/store/account/subscriptions', {
          'package': 'com.bishare.app',
          'sku': ?productId,
        })
      : Uri.https('apps.apple.com', '/account/subscriptions');

  final VaultAccount _account;
  final VaultApi _api;
  final InAppPurchase? _storeOverride;
  InAppPurchase get _store => _storeOverride ?? InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// The store answered and these products are on sale in this country.
  bool available = false;
  bool loading = false;
  Map<String, ProductDetails> products = const {};

  /// A purchase in progress (the store's sheet is up, or the server is
  /// checking it).
  String? busyProduct;
  bool restoring = false;

  /// Why the last purchase or restore did not go through: a server code
  /// (`VAULT_PURCHASE_OTHER_ACCOUNT`, `NETWORK`, …) or `STORE`.
  String? lastError;

  /// From app start: the stores hand over unfinished purchases (a renewal,
  /// a purchase cut off by a crash) as soon as anyone listens.
  void start() {
    if (!supported || _sub != null) return;
    _account.addListener(_onAccount);
    _sub = _store.purchaseStream.listen(
      (list) => unawaited(_onPurchases(list)),
      onError: (Object e) => debugPrint('[vault] store: $e'),
    );
  }

  /// Purchases the store handed over before this run knew its Drive (the
  /// account still loading at start, audit P13): reported once it does,
  /// rather than left unfinished until the next start.
  final List<PurchaseDetails> _waiting = [];

  void _onAccount() {
    if (_account.vaultId == null || _waiting.isEmpty) return;
    final waiting = [..._waiting];
    _waiting.clear();
    for (final p in waiting) {
      unawaited(_report(p));
    }
  }

  /// The plans with this country's prices.
  Future<void> load() async {
    if (!supported || loading) return;
    loading = true;
    notifyListeners();
    try {
      available = await _store.isAvailable();
      if (available) {
        final r = await _store.queryProductDetails(productIds);
        products = {for (final p in r.productDetails) p.id: p};
        if (r.notFoundIDs.isNotEmpty) {
          debugPrint('[vault] not on sale here: ${r.notFoundIDs}');
        }
      }
    } on Object catch (e) {
      debugPrint('[vault] store: $e');
      available = false;
    }
    loading = false;
    notifyListeners();
  }

  /// Start buying [productId]. On Google a change from the current plan
  /// replaces it: a bigger plan at once (the rest of the old one is credited),
  /// a smaller one at the next renewal. On Apple the subscription group does
  /// the same by itself.
  Future<void> buy(String productId) async {
    final details = products[productId];
    final vaultId = _account.vaultId;
    if (details == null || vaultId == null || busyProduct != null) return;
    busyProduct = productId;
    lastError = null;
    notifyListeners();
    try {
      final user = _android ? vaultId : vaultUuid(vaultId);
      var param = PurchaseParam(
        productDetails: details,
        applicationUserName: user,
      );
      if (_android) {
        final old = await _currentGooglePurchase();
        if (old != null && old.productID != productId) {
          final bigger = sizeOf(productId) >= sizeOf(old.productID);
          param = GooglePlayPurchaseParam(
            productDetails: details,
            applicationUserName: user,
            changeSubscriptionParam: ChangeSubscriptionParam(
              oldPurchaseDetails: old,
              replacementMode: bigger
                  ? ReplacementMode.withTimeProration
                  : ReplacementMode.deferred,
            ),
          );
        }
      }
      await _store.buyNonConsumable(purchaseParam: param);
    } on Object catch (e) {
      debugPrint('[vault] buy: $e');
      busyProduct = null;
      lastError = 'STORE';
      notifyListeners();
    }
  }

  /// "Restore purchases": the store hands over what this account bought, and
  /// each is checked by the server like a new purchase.
  Future<void> restore() async {
    if (!supported || restoring) return;
    restoring = true;
    lastError = null;
    notifyListeners();
    try {
      await _store.restorePurchases();
      // The results come through the purchase stream; give them a moment.
      await Future<void>.delayed(const Duration(seconds: 3));
      await _account.refreshInfo();
    } on Object catch (e) {
      debugPrint('[vault] restore: $e');
      lastError = e is VaultApiException ? e.code : 'STORE';
    }
    restoring = false;
    notifyListeners();
  }

  /// Android: the purchase tokens of this Drive's plans on this Play account,
  /// for the server to stop them renewing when the Drive is deleted.
  Future<List<String>> googleTokens() async {
    if (!supported || !_android) return const [];
    try {
      final addition = _store
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final past = await addition.queryPastPurchases();
      final vaultId = _account.vaultId;
      return [
        for (final p in past.pastPurchases)
          if (productIds.contains(p.productID) &&
              p.billingClientPurchase.obfuscatedAccountId == vaultId)
            p.verificationData.serverVerificationData,
      ];
    } on Object catch (e) {
      debugPrint('[vault] past purchases: $e');
      return const [];
    }
  }

  Future<GooglePlayPurchaseDetails?> _currentGooglePurchase() async {
    final addition = _store
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final past = await addition.queryPastPurchases();
    // Only this Drive's plan: one Play account may pay for two Drives, and
    // replacing the other one's would end its plan (audit P7).
    final vaultId = _account.vaultId;
    final mine = past.pastPurchases
        .where(
          (p) =>
              productIds.contains(p.productID) &&
              p.billingClientPurchase.obfuscatedAccountId == vaultId,
        )
        .toList();
    if (mine.isEmpty) return null;
    return mine.firstWhere(
      (p) => p.productID == _account.plan,
      orElse: () => mine.first,
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busyProduct = p.productID;
          notifyListeners();
        case PurchaseStatus.canceled:
        case PurchaseStatus.error:
          if (p.status == PurchaseStatus.error) lastError = 'STORE';
          // Google Play reports a closed sheet or a refusal without the
          // product (audit P2): whatever was in progress is over.
          if (p.productID.isEmpty || busyProduct == p.productID) {
            busyProduct = null;
          }
          await _finish(p);
          notifyListeners();
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _report(p);
      }
    }
  }

  Future<void> _report(PurchaseDetails p) async {
    if (!productIds.contains(p.productID)) {
      // "Nothing bought" from Google Play (an item already owned, a change
      // that waits for the renewal) comes without a product too.
      if (p.productID.isEmpty && busyProduct != null) {
        busyProduct = null;
        notifyListeners();
      }
      return _finish(p);
    }
    final vaultId = _account.vaultId;
    // No Drive known yet on this run: reported when there is one (or, signed
    // out, the store offers it again once a Drive is open here).
    if (vaultId == null) {
      _waiting.add(p);
      return;
    }
    final proof = p.verificationData.serverVerificationData;
    try {
      final plan = await _api.entitlement(
        vaultId,
        _android
            ? {'store': 'google', 'purchaseToken': proof}
            : {'store': 'apple', 'signedTransaction': proof},
      );
      _account.applyPlan(plan);
      await _finish(p);
      unawaited(_account.refreshInfo().catchError((Object _) {}));
    } on VaultApiException catch (e) {
      lastError = e.code;
      // Bought for another Drive, already funding one, or not a Drive plan:
      // nothing more this Drive can do with it. Anything else (no network,
      // the server busy) is kept to be handed over again.
      const settled = {
        'VAULT_PURCHASE_OTHER_ACCOUNT',
        'VAULT_PURCHASE_IN_USE',
        'VAULT_PURCHASE_INVALID',
        'VAULT_PURCHASE_NOT_FOUND',
      };
      if (settled.contains(e.code)) await _finish(p);
    } finally {
      if (busyProduct == p.productID) busyProduct = null;
      notifyListeners();
    }
  }

  Future<void> _finish(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await _store.completePurchase(p);
    } on Object catch (e) {
      debugPrint('[vault] finish: $e');
    }
  }

  @override
  void dispose() {
    _account.removeListener(_onAccount);
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

/// The vault id's 16 bytes as a UUID: Apple's appAccountToken must be one
/// (bishare-api store.ts vaultUuid, the same bytes).
String vaultUuid(String vaultId) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  final out = <int>[];
  var buf = 0;
  var bits = 0;
  for (final ch in vaultId.split('')) {
    final v = alphabet.indexOf(ch);
    if (v < 0) throw ArgumentError.value(vaultId, 'vaultId');
    buf = ((buf << 5) | v) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buf >> bits) & 0xff);
    }
  }
  final h = out.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20, 32)}';
}
