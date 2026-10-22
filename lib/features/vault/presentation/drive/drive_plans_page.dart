import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_links.dart';
import '../../../../core/di/locator.dart';
import '../../../../core/ui/app_ui.dart';
import '../../data/vault_account.dart';
import '../../data/vault_purchases.dart';
import 'drive_format.dart';

/// Drive plans (drive-plan.md task 7.1): what the Drive has now, the four
/// sizes at this country's store prices, monthly or yearly, and what the
/// stores require next to a subscription: the renewal terms, Terms and
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
  String? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plan = _account.plan;
    _purchases.addListener(_onPurchases);
    _account.addListener(_onAccount);
    unawaited(_purchases.load());
    unawaited(_account.refreshInfo().catchError((Object _) {}));
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 720,
          child: Column(
            children: [
              AppScreenHeader(
                title: 'vault.plans_title'.tr(),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: Listenable.merge([_account, _purchases]),
                  builder: (context, _) => ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 32),
                    children: [
                      _current(cs),
                      const SizedBox(height: 18),
                      ..._offer(cs),
                      const SizedBox(height: 18),
                      _includes(cs),
                      if (VaultPurchases.supported) _legal(cs),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- the plan now ------------------------------------------------------------------

  Widget _current(ShadColorScheme cs) {
    final plan = _account.plan ?? 'free';
    final quota = _account.quotaBytes;
    final paid = plan != 'free';
    final muted = ShadTheme.of(context).textTheme.muted.copyWith(fontSize: 13);
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
    return AppGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'vault.plans_now'.tr(),
                  style: muted.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (paid)
                  AppBadge(
                    (VaultPurchases.isYearly(plan)
                            ? 'vault.plans_yearly'
                            : 'vault.plans_monthly')
                        .tr(),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              paid
                  ? decimalBytes(VaultPurchases.sizeOf(plan))
                  : 'vault.plan_free_size'.tr(
                      namedArgs: {'size': decimalBytes(quota ?? 5000000000)},
                    ),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            if (line != null) ...[
              const SizedBox(height: 6),
              Text(
                line,
                style: muted.copyWith(
                  color: warn ? cs.destructive : null,
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
                  onPressed: () =>
                      _open(VaultPurchases.manageUri(_account.plan)),
                )
              else
                Text(
                  'vault.plans_other_store_$store'.tr(),
                  style: muted.copyWith(height: 1.35),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- the four sizes ------------------------------------------------------------------

  List<Widget> _offer(ShadColorScheme cs) {
    final muted = ShadTheme.of(context).textTheme.muted.copyWith(fontSize: 13);
    if (!VaultPurchases.supported) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            'vault.plans_desktop'.tr(),
            style: muted.copyWith(height: 1.4),
          ),
        ),
      ];
    }
    final store = _account.planStore;
    final paid = (_account.plan ?? 'free') != 'free';
    // A plan billed by the other store is changed there, never bought twice.
    final elsewhere =
        paid &&
        store != null &&
        store != VaultPurchases.storeHere &&
        store != 'test';
    if (_purchases.products.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: _purchases.loading
              ? const Center(child: CircularProgressIndicator.adaptive())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('vault.plans_store_down'.tr(), style: muted),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'vault.plans_retry'.tr(),
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.small,
                      onPressed: () => unawaited(_purchases.load()),
                    ),
                  ],
                ),
        ),
      ];
    }
    return [
      _PeriodSwitch(
        yearly: _yearly,
        onChanged: (v) => setState(() => _yearly = v),
      ),
      const SizedBox(height: 12),
      for (final size in VaultPurchases.sizes)
        _PlanCard(
          size: size,
          details: _purchases
              .products[VaultPurchases.productFor(size, yearly: _yearly)],
          yearly: _yearly,
          current:
              _account.plan == VaultPurchases.productFor(size, yearly: _yearly),
          busy:
              _purchases.busyProduct ==
              VaultPurchases.productFor(size, yearly: _yearly),
          enabled: !elsewhere && _purchases.busyProduct == null,
          onChoose: () => unawaited(
            _purchases.buy(VaultPurchases.productFor(size, yearly: _yearly)),
          ),
        ),
      if (paid && !elsewhere)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
          child: Text(
            'vault.plans_change_note'.tr(),
            style: muted.copyWith(fontSize: 12, height: 1.35),
          ),
        ),
    ];
  }

  // ---- every plan has ------------------------------------------------------------------

  Widget _includes(ShadColorScheme cs) {
    const keys = ['e2e', 'photos', 'devices', 'trash'];
    return AppGroup(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'vault.plans_includes'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final k in keys)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: AppSvgIcon(
                        AppIcons.check,
                        size: 15,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('vault.plans_inc_$k'.tr())),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- what the stores require next to a subscription ------------------------------------

  Widget _legal(ShadColorScheme cs) {
    final muted = ShadTheme.of(
      context,
    ).textTheme.muted.copyWith(fontSize: 12, height: 1.4);
    final link = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: cs.primary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'vault.plans_legal_${VaultPurchases.storeHere}'.tr(),
            style: muted,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              InkWell(
                onTap: () => _open(Uri.parse(AppLinks.terms)),
                child: Text('vault.plans_terms'.tr(), style: link),
              ),
              InkWell(
                onTap: () => _open(Uri.parse(AppLinks.privacy)),
                child: Text('vault.plans_privacy'.tr(), style: link),
              ),
              InkWell(
                onTap: _purchases.restoring
                    ? null
                    : () async {
                        await _purchases.restore();
                        if (mounted && _purchases.lastError == null) {
                          toast(context, 'vault.plans_restored'.tr());
                        }
                      },
                child: Text(
                  _purchases.restoring
                      ? 'vault.plans_restoring'.tr()
                      : 'vault.plans_restore'.tr(),
                  style: link,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.yearly, required this.onChanged});

  final bool yearly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    Widget part(bool value, String label, {String? note}) {
      final on = yearly == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: on ? cs.background : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: on
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: on ? cs.foreground : cs.mutedForeground,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.muted,
        borderRadius: BorderRadius.circular(13),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            part(false, 'vault.plans_monthly'.tr()),
            part(
              true,
              'vault.plans_yearly'.tr(),
              note: 'vault.plans_yearly_save'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.size,
    required this.details,
    required this.yearly,
    required this.current,
    required this.busy,
    required this.enabled,
    required this.onChoose,
  });

  final int size;
  final ProductDetails? details;
  final bool yearly;
  final bool current;
  final bool busy;
  final bool enabled;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final price = details?.price;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: current ? cs.primary : cs.border.withValues(alpha: 0.8),
          width: current ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  decimalBytes(size),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  price == null
                      ? 'vault.plans_unavailable'.tr()
                      : (yearly
                                ? 'vault.plans_per_year'
                                : 'vault.plans_per_month')
                            .tr(namedArgs: {'price': price}),
                  style: TextStyle(color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          if (current)
            AppBadge('vault.plans_current'.tr())
          else
            AppButton(
              label: 'vault.plans_choose'.tr(),
              size: AppButtonSize.small,
              loading: busy,
              disabled: !enabled || details == null,
              onPressed: onChoose,
            ),
        ],
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
      final cs = ShadTheme.of(context).colorScheme;
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
            color: cs.destructive.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.destructive.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              AppSvgIcon(AppIcons.circleAlert, size: 18, color: cs.destructive),
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
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
