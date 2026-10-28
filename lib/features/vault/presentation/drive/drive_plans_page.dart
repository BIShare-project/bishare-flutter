import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_links.dart';
import '../../../../core/di/locator.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_account.dart';
import '../../data/vault_purchases.dart';
import 'drive_format.dart';

/// Drive plans (drive-plan.md task 7.1): what the Drive has now, the four
/// sizes at this country's store prices, monthly or yearly, and one button
/// for the size picked, with what the stores require next to a subscription:
/// the price and the renewal by the button, the renewal terms, Terms and
/// Privacy, and Restore. Windows and Linux only say where a plan is bought.
class DrivePlansPage extends StatefulWidget {
  const DrivePlansPage({super.key});

  @override
  State<DrivePlansPage> createState() => _DrivePlansPageState();
}

class _DrivePlansPageState extends State<DrivePlansPage> {
  final VaultAccount _account = getIt<VaultAccount>();
  final VaultPurchases _purchases = getIt<VaultPurchases>();
  late bool _yearly = VaultPurchases.isYearly(_account.plan ?? '');

  /// The size picked: the plan in force, else [_recommended].
  late int _size = _paidSize ?? _recommended;
  String? _plan;
  String? _error;

  /// The size the page suggests, and picks first.
  static const _recommended = 250 * 1000000000;

  @override
  void initState() {
    super.initState();
    _plan = _account.plan;
    _purchases.addListener(_onPurchases);
    _account.addListener(_onAccount);
    unawaited(_purchases.load());
    unawaited(_account.refreshInfo().catchError((Object _) {}));
    _usage = _account.followUsage();
  }

  /// The fill under the title follows uploads (VaultAccount.followUsage).
  StreamSubscription<Object?>? _usage;

  @override
  void dispose() {
    unawaited(_usage?.cancel());
    _purchases.removeListener(_onPurchases);
    _account.removeListener(_onAccount);
    super.dispose();
  }

  /// A purchase that went through shows as the plan changing.
  void _onAccount() {
    final plan = _account.plan;
    if (plan != _plan && plan != null && plan != 'free' && mounted) {
      toast(
        context,
        'vault.plans_active'.tr(
          namedArgs: {'size': decimalBytes(VaultPurchases.sizeOf(plan))},
        ),
        type: ToastType.success,
      );
    }
    _plan = plan;
  }

  void _onPurchases() {
    final error = _purchases.lastError;
    if (error != null && error != _error && mounted) {
      toast(context, _errorText(error), type: ToastType.error);
    }
    _error = error;
  }

  String _errorText(String code) => switch (code) {
    'VAULT_PURCHASE_OTHER_ACCOUNT' => 'vault.plans_err_other_account'.tr(),
    'VAULT_PURCHASE_IN_USE' => 'vault.plans_err_in_use'.tr(),
    'NETWORK' => 'vault.plans_err_network'.tr(),
    'STORE' => 'vault.plans_err_store'.tr(),
    'VAULT_STORE_UNAVAILABLE' => 'vault.plans_err_closed'.tr(),
    _ => 'vault.plans_err_other'.tr(),
  };

  Future<void> _open(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  String _date(DateTime d) =>
      DateFormat.yMMMd(context.locale.toLanguageTag()).format(d);

  Future<void> _restore() async {
    await _purchases.restore();
    if (mounted && _purchases.lastError == null) {
      toast(context, 'vault.plans_restored'.tr());
    }
  }

  /// The size of the paid plan in force, when it is one on sale.
  int? get _paidSize {
    final plan = _account.plan ?? 'free';
    if (plan == 'free') return null;
    final size = VaultPurchases.sizeOf(plan);
    return VaultPurchases.sizes.contains(size) ? size : null;
  }

  /// A plan billed by the other store is changed there, never bought twice.
  bool get _elsewhere {
    final store = _account.planStore;
    return (_account.plan ?? 'free') != 'free' &&
        store != null &&
        store != VaultPurchases.storeHere &&
        store != 'test';
  }

  String get _product => VaultPurchases.productFor(_size, yearly: _yearly);

  /// The button shows once this store has something to sell here.
  bool get _canBuy =>
      VaultPurchases.supported && _purchases.products.isNotEmpty && !_elsewhere;

  /// The price as the store bills it: "$5.99 a month", "$59.99 a year".
  String _billed(ProductDetails p, {required bool yearly}) =>
      (yearly ? 'vault.plans_per_year' : 'vault.plans_per_month').tr(
        namedArgs: {'price': p.price},
      );

  /// A yearly price as a twelfth, in the store's currency; null when the
  /// store gave no number to work it out from.
  String? _perMonth(ProductDetails p) {
    if (p.rawPrice <= 0 || p.currencyCode.isEmpty) return null;
    try {
      return NumberFormat.simpleCurrency(
        locale: context.locale.toLanguageTag(),
        name: p.currencyCode,
      ).format(p.rawPrice / 12);
    } on Object {
      return null;
    }
  }

  /// What a year saves on twelve months, from this country's prices: the
  /// smallest whole percent across the sizes, so it holds for each of them.
  int? get _yearlySaving {
    int? least;
    for (final size in VaultPurchases.sizes) {
      final month =
          _purchases.products[VaultPurchases.productFor(size, yearly: false)];
      final year =
          _purchases.products[VaultPurchases.productFor(size, yearly: true)];
      if (month == null || year == null || month.rawPrice <= 0) continue;
      if (month.currencyCode != year.currencyCode) continue;
      final pct = ((1 - year.rawPrice / (month.rawPrice * 12)) * 100).floor();
      least = least == null ? pct : math.min(least, pct);
    }
    return least != null && least > 0 ? least : null;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: AppResponsivePane(
          maxWidth: 600,
          child: ListenableBuilder(
            listenable: Listenable.merge([_account, _purchases]),
            builder: (context, _) {
              final buy = _canBuy;
              final current = _showCurrent;
              final inset = MediaQuery.paddingOf(context).bottom;
              final dark = Theme.of(context).brightness == Brightness.dark;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The accent glows behind the top of the page.
                  Positioned(
                    top: -150,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 460,
                          height: 460,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                t.accent.withValues(
                                  alpha: dark ? 0.24 : 0.13,
                                ),
                                t.accent.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      _topBar(t),
                      Expanded(
                        child: Stack(
                          children: [
                            ListView(
                              padding: EdgeInsets.only(
                                bottom: buy ? 28 : 32 + inset,
                              ),
                              children: [
                                _hero(t, usage: !current),
                                if (current) ...[
                                  _current(t),
                                  const SizedBox(height: 22),
                                ],
                                ..._offer(t),
                                const SizedBox(height: 26),
                                _includes(t),
                                if (VaultPurchases.supported) _legal(t),
                              ],
                            ),
                            if (buy)
                              // The list fades out above the button.
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 28,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          t.bg.withValues(alpha: 0),
                                          t.bg,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (buy) _buyBar(t, inset),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppTokens t) {
    final restoring = _purchases.restoring;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 10, 0),
      child: Row(
        children: [
          AppIconButton(icon: AppIcons.chevronLeft, onPressed: () => Navigator.of(context).maybePop(),),
          const Spacer(),
          if (VaultPurchases.supported)
            _Link(
              restoring
                  ? 'vault.plans_restoring'.tr()
                  : 'vault.plans_restore'.tr(),
              restoring ? null : () => unawaited(_restore()),
              size: 13.5,
            ),
        ],
      ),
    );
  }

  // ---- what a plan buys ------------------------------------------------------------------

  /// [usage]: the free Drive's fill, when there is no plan card to show it.
  Widget _hero(AppTokens t, {required bool usage}) {
    final quota = _account.quotaBytes ?? 0;
    final used = _account.usedBytes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 24),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: _brand(t.accent),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.42),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                  spreadRadius: -10,
                ),
              ],
            ),
            child: Center(
              child: AppSvgIcon(
                AppIcons.cloudDone,
                size: 34,
                color: _on(t.accent),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'vault.plans_hero_title'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            // A phone's width of text, wrapped evenly on a wide window too.
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              'vault.plans_hero_sub'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: t.text2,
              ),
            ),
          ),
          if (usage && quota > 0 && used != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 14, 7),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: t.line.withValues(alpha: 0.8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    child: _UsageBar(share: used / quota, color: t.accent),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'vault.quota_line'.tr(
                        namedArgs: {
                          'used': decimalBytes(used),
                          'quota': decimalBytes(quota),
                        },
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.text.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- the plan now ------------------------------------------------------------------

  /// A plan, or a Drive whose plan is in trouble, gets its own card; the
  /// free Drive's fill sits under the title.
  bool get _showCurrent =>
      (_account.plan ?? 'free') != 'free' ||
      _account.state == 'grace' ||
      _account.state == 'lapsed';

  Widget _current(AppTokens t) {
    final plan = _account.plan ?? 'free';
    final quota = _account.quotaBytes ?? 0;
    final used = _account.usedBytes;
    final paid = plan != 'free';
    final muted = AppType.secondary.copyWith(color: context.tokens.text2).copyWith(fontSize: 13);
    final ends = _account.planEnds;
    final lapse = _account.lapseEnds;
    final store = _account.planStore;
    final String? line = switch (_account.state) {
      'grace' => 'vault.plans_grace'.tr(),
      'lapsed' when lapse != null => 'vault.plans_lapsed'.tr(
        namedArgs: {'date': _date(lapse), 'size': decimalBytes(5000000000)},
      ),
      _ when paid && ends != null =>
        (_account.planRenews == false
                ? 'vault.plans_ends'
                : 'vault.plans_renews')
            .tr(namedArgs: {'date': _date(ends)}),
      _ => null,
    };
    final warn = _account.state == 'grace' || _account.state == 'lapsed';
    final here = store == VaultPurchases.storeHere;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: warn
              ? t.danger.withValues(alpha: 0.5)
              : t.line.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'vault.plans_now'.tr(),
                  style: muted.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (paid)
                AppBadge(
                  (VaultPurchases.isYearly(plan)
                          ? 'vault.plans_yearly'
                          : 'vault.plans_monthly')
                      .tr(),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            paid
                ? decimalBytes(VaultPurchases.sizeOf(plan))
                : 'vault.plan_free_size'.tr(
                    namedArgs: {
                      'size': decimalBytes(quota > 0 ? quota : 5000000000),
                    },
                  ),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: t.text,
            ),
          ),
          if (quota > 0 && used != null) ...[
            const SizedBox(height: 10),
            _UsageBar(
              share: used / quota,
              color: warn ? t.danger : t.accent,
            ),
            const SizedBox(height: 6),
            Text(
              'vault.quota_line'.tr(
                namedArgs: {
                  'used': decimalBytes(used),
                  'quota': decimalBytes(quota),
                },
              ),
              style: muted.copyWith(fontSize: 12.5),
            ),
          ],
          if (line != null) ...[
            const SizedBox(height: 8),
            Text(
              line,
              style: muted.copyWith(
                color: warn ? t.danger : null,
                height: 1.35,
              ),
            ),
          ],
          if (paid && store != null && store != 'test') ...[
            const SizedBox(height: 12),
            if (here && VaultPurchases.supported)
              AppButton(
                label: 'vault.plans_manage'.tr(),
                icon: AppIcons.externalLink,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
                onPressed: () => _open(VaultPurchases.manageUri(_account.plan)),
              )
            else
              Text(
                'vault.plans_other_store_$store'.tr(),
                style: muted.copyWith(height: 1.35),
              ),
          ],
        ],
      ),
    );
  }

  // ---- the four sizes ------------------------------------------------------------------

  List<Widget> _offer(AppTokens t) {
    if (!VaultPurchases.supported) {
      return [
        _Note(icon: AppIcons.smartphone, text: 'vault.plans_desktop'.tr()),
      ];
    }
    if (_purchases.products.isEmpty) {
      if (_purchases.loading) {
        return [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ];
      }
      return [
        _Note(
          icon: AppIcons.circleAlert,
          text: 'vault.plans_store_down'.tr(),
          action: AppButton(
            label: 'vault.plans_retry'.tr(),
            variant: AppButtonVariant.outline,
            size: AppButtonSize.small,
            onPressed: () => unawaited(_purchases.load()),
          ),
        ),
      ];
    }
    final elsewhere = _elsewhere;
    final saving = _yearlySaving;
    return [
      _PeriodSwitch(
        yearly: _yearly,
        saving: saving == null
            ? null
            : 'vault.plans_save'.tr(namedArgs: {'pct': '$saving'}),
        onChanged: (v) => setState(() => _yearly = v),
      ),
      const SizedBox(height: 14),
      for (final size in VaultPurchases.sizes) _sizeCard(size, elsewhere),
      if (_paidSize != null && !elsewhere)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 0),
          child: Text(
            'vault.plans_change_note'.tr(),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: t.text2,
            ),
          ),
        ),
    ];
  }

  Widget _sizeCard(int size, bool elsewhere) {
    final id = VaultPurchases.productFor(size, yearly: _yearly);
    final details = _purchases.products[id];
    final month = _yearly && details != null ? _perMonth(details) : null;
    return _PlanCard(
      size: size,
      billed: details == null
          ? 'vault.plans_unavailable'.tr()
          : _billed(details, yearly: _yearly),
      perMonth: month == null
          ? null
          : 'vault.plans_month_equiv'.tr(namedArgs: {'price': month}),
      selected: size == _size,
      current: _account.plan == id,
      recommended: size == _recommended,
      onTap: elsewhere ? null : () => setState(() => _size = size),
    );
  }

  // ---- the button ------------------------------------------------------------------

  Widget _buyBar(AppTokens t, double inset) {
    final id = _product;
    final details = _purchases.products[id];
    final current = _account.plan == id;
    final paid = _paidSize;
    final label = current
        ? 'vault.plans_cta_current'.tr()
        : paid == null
        ? 'vault.plans_cta_get'.tr(namedArgs: {'size': decimalBytes(_size)})
        : paid == _size
        ? (_yearly ? 'vault.plans_cta_yearly' : 'vault.plans_cta_monthly').tr()
        : 'vault.plans_cta_switch'.tr(namedArgs: {'size': decimalBytes(_size)});
    return Container(
      color: t.bg,
      padding: EdgeInsets.fromLTRB(16, 2, 16, 12 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BuyButton(
            label: label,
            // The price as billed, right under what it buys (owner: "biar
            // jelas"); the plan in force needs none.
            price: current
                ? null
                : details == null
                ? 'vault.plans_unavailable'.tr()
                : _billed(details, yearly: _yearly),
            loading: _purchases.busyProduct == id,
            onPressed:
                details == null || current || _purchases.busyProduct != null
                ? null
                : () => unawaited(_purchases.buy(id)),
          ),
          const SizedBox(height: 9),
          Text(
            'vault.plans_cta_note'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: t.text2,
            ),
          ),
        ],
      ),
    );
  }

  // ---- every plan has ------------------------------------------------------------------

  Widget _includes(AppTokens t) {
    const items = [
      ('e2e', AppIcons.passwordLock),
      ('photos', AppIcons.image),
      ('devices', AppIcons.monitor),
      ('trash', AppIcons.trashDelete),
    ];
    return AppGroup(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'vault.plans_includes'.tr(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 12),
            for (final (key, icon) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Center(
                        child: AppSvgIcon(icon, size: 18, color: t.accent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'vault.plans_inc_$key'.tr(),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: t.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- what the stores require next to a subscription ------------------------------------

  Widget _legal(AppTokens t) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text(
              'vault.plans_legal_${VaultPurchases.storeHere}'.tr(),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: t.text2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(
              children: [
                _Link(
                  'vault.plans_terms'.tr(),
                  () => _open(Uri.parse(AppLinks.terms)),
                ),
                _Link(
                  'vault.plans_privacy'.tr(),
                  () => _open(Uri.parse(AppLinks.privacy)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// BIShare blue running into indigo: the paywall's badge, ribbon and button.
LinearGradient _brand(Color primary) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color.lerp(primary, Colors.white, 0.1)!,
    primary,
    Color.lerp(primary, const Color(0xFF3730A3), 0.45)!,
  ],
);

/// Text and icons on [_brand]: white unless the accent is a light one.
Color _on(Color primary) =>
    ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
    ? Colors.white
    : Colors.black87;

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({
    required this.yearly,
    required this.saving,
    required this.onChanged,
  });

  final bool yearly;

  /// "Save 16%", when this country's prices show a saving.
  final String? saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? const Color(0xFF30D158) : const Color(0xFF1E8E3E);
    Widget part(bool value, String label, {String? note}) {
      final on = yearly == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (on) return;
              tapHaptic();
              onChanged(value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: on ? t.text : t.text2,
                      ),
                    ),
                    if (note != null) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              alignment: yearly
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark
                        ? Color.alphaBlend(
                            Colors.white.withValues(alpha: 0.09),
                            t.sunken,
                          )
                        : t.bg,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: t.line.withValues(alpha: dark ? 0.9 : 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              part(false, 'vault.plans_monthly'.tr()),
              part(true, 'vault.plans_yearly'.tr(), note: saving),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.size,
    required this.billed,
    required this.perMonth,
    required this.selected,
    required this.current,
    required this.recommended,
    required this.onTap,
  });

  final int size;

  /// The price as billed ("$59.99 a year"), or why there is none.
  final String billed;

  /// A yearly price as a twelfth ("$5.00 a month, billed yearly").
  final String? perMonth;
  final bool selected;
  final bool current;
  final bool recommended;

  /// Null when the plans are changed in the other store.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = selected && onTap != null;
    final radius = BorderRadius.circular(18);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Semantics(
        button: onTap != null,
        selected: on,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap == null
                ? null
                : () {
                    tapHaptic();
                    onTap!();
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 16, 14),
              decoration: BoxDecoration(
                color: on
                    ? Color.alphaBlend(
                        t.accent.withValues(alpha: 0.08),
                        t.surface,
                      )
                    : t.surface,
                borderRadius: radius,
                border: Border.all(
                  color: on ? t.accent : t.line.withValues(alpha: 0.8),
                  width: on ? 2 : 1,
                ),
                boxShadow: on
                    ? [
                        BoxShadow(
                          color: t.accent.withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          spreadRadius: -8,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  _Radio(on: on),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              decimalBytes(size),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: t.text,
                              ),
                            ),
                            if (current)
                              AppBadge('vault.plans_current'.tr())
                            else if (recommended)
                              _Ribbon('vault.plans_recommended'.tr()),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          billed,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: t.text.withValues(
                              alpha: on ? 1 : 0.85,
                            ),
                          ),
                        ),
                        if (perMonth != null) ...[
                          const SizedBox(height: 1),
                          Text(
                            perMonth!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: t.text2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: on ? _brand(t.accent) : null,
        border: on ? null : Border.all(color: t.line, width: 2),
      ),
      child: on
          ? Center(
              child: AppSvgIcon(
                AppIcons.check,
                size: 14,
                color: _on(t.accent),
              ),
            )
          : null,
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = context.tokens.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: _brand(primary),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          color: _on(primary),
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.share, required this.color});

  /// Used over quota; more than 1 when over.
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fill = share <= 0 ? 0.0 : share.clamp(0.02, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: context.tokens.line)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: fill,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.7), color],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({
    required this.label,
    required this.price,
    required this.loading,
    required this.onPressed,
  });

  final String label;

  /// Under [label]: "$19.99 a month".
  final String? price;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onPressed != null && !loading;
    // Nothing to buy (the plan in force, or not on sale): a plain grey bar.
    final idle = onPressed == null && !loading;
    final radius = BorderRadius.circular(16);
    final fg = idle ? t.text2 : _on(t.accent);
    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: price == null ? 54 : 62,
        decoration: BoxDecoration(
          color: idle ? t.sunken : null,
          gradient: idle ? null : _brand(t.accent),
          borderRadius: radius,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.38),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                    spreadRadius: -10,
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: enabled
                ? () {
                    tapHaptic();
                    onPressed!();
                  }
                : null,
            child: Center(
              child: loading
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: fg,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                              color: fg,
                            ),
                          ),
                          if (price != null)
                            Text(
                              price!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: fg.withValues(alpha: 0.85),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of the page in a tinted card: where desktops buy, a store that
/// did not answer.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.action});

  final String icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSvgIcon(icon, size: 20, color: t.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: t.text,
                  ),
                ),
                if (action != null) ...[const SizedBox(height: 10), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.onTap, {this.size = 12.5});

  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w600,
            color: onTap == null ? t.text2 : t.accent,
          ),
        ),
      ),
    );
  }
}

/// On the Drive itself (task 7.6): a plan whose renewal failed (grace: it
/// still works while the store retries), or one that ended with more than
/// the free size stored (read-only until [VaultAccount.lapseEnds]).
class DrivePlanNotice extends StatelessWidget {
  const DrivePlanNotice({super.key, required this.account});

  final VaultAccount account;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: account,
    builder: (context, _) {
      final state = account.state;
      final lapse = account.lapseEnds;
      if (state != 'grace' && !(state == 'lapsed' && lapse != null)) {
        return const SizedBox.shrink();
      }
      final t = context.tokens;
      final text = state == 'grace'
          ? 'vault.plans_grace'.tr()
          : 'vault.plans_lapsed'.tr(
              namedArgs: {
                'date': DateFormat.yMMMd(
                  context.locale.toLanguageTag(),
                ).format(lapse!),
                'size': decimalBytes(5000000000),
              },
            );
      return InkWell(
        onTap: () => context.push('/drive-plans'),
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: t.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.danger.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              AppSvgIcon(AppIcons.circleAlert, size: 18, color: t.danger),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'vault.plans_see'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.accent,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
