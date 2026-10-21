import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../../settings/presentation/widgets/glyph.dart';
import '../data/vault_account.dart';
import '../data/vault_api.dart';
import '../data/vault_signin.dart';

/// The Drive group in Settings (drive-plan.md phase 3, for testers). Renders
/// nothing at all unless [FeatureFlags.vaultVisible]: with the flag off the
/// Settings page is exactly what it was, and no Drive object is even created.
class VaultSection extends StatelessWidget {
  const VaultSection({super.key});

  @override
  Widget build(BuildContext context) {
    final flags = getIt<FeatureFlags>();
    return ListenableBuilder(
      listenable: flags,
      builder: (context, _) =>
          flags.vaultVisible ? const _VaultGroup() : const SizedBox.shrink(),
    );
  }
}

class _VaultGroup extends StatefulWidget {
  const _VaultGroup();

  @override
  State<_VaultGroup> createState() => _VaultGroupState();
}

class _VaultGroupState extends State<_VaultGroup> {
  final VaultAccount _account = getIt<VaultAccount>();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_account.load());
  }

  Future<void> _signIn(String provider) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _account.signIn(provider);
    } on VaultApiException catch (e) {
      _error = switch (e.code) {
        'VAULT_UNAVAILABLE' => 'vault.error_unavailable'.tr(),
        'VAULT_NOT_INVITED' => 'vault.error_not_invited'.tr(),
        'NETWORK' => 'vault.error_network'.tr(),
        _ => 'vault.error_generic'.tr(),
      };
      // In internal mode the refusal carries the subject hash the owner adds to
      // vault_testers; it is only printed (debug log), never shown.
      debugPrint('[vault] sign-in refused: $e ${e.extra['subjectHash'] ?? ''}');
    } on VaultSigninException catch (e) {
      _error = 'vault.error_generic'.tr();
      debugPrint('[vault] provider sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = ShadTheme.of(context).textTheme.muted.copyWith(fontSize: 12);
    return ListenableBuilder(
      listenable: _account,
      builder: (context, _) {
        final status = _account.status;
        final rows = <Widget>[];
        if (status == VaultStatus.signedOut) {
          rows.add(
            AppListTile(
              leading: const Glyph(AppIcons.passwordLock),
              title: Text('vault.title'.tr()),
              subtitle: Text('vault.signed_out'.tr()),
            ),
          );
          final buttons = <Widget>[
            if (VaultSignin.googleAvailable)
              AppButton(
                label: 'vault.sign_in_google'.tr(),
                variant: AppButtonVariant.outline,
                fullWidth: true,
                loading: _busy,
                onPressed: _busy ? null : () => _signIn('google'),
              ),
            if (VaultSignin.appleAvailable)
              AppButton(
                label: 'vault.sign_in_apple'.tr(),
                variant: AppButtonVariant.outline,
                fullWidth: true,
                loading: _busy,
                onPressed: _busy ? null : () => _signIn('apple'),
              ),
          ];
          rows.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                children: [
                  for (final b in buttons)
                    Padding(padding: const EdgeInsets.only(top: 8), child: b),
                ],
              ),
            ),
          );
        } else {
          rows.add(
            AppListTile(
              leading: const Glyph(AppIcons.passwordLock),
              title: Text('vault.title'.tr()),
              subtitle: Text(switch (status) {
                VaultStatus.ready => 'vault.ready'.tr(),
                VaultStatus.needsKey => 'vault.needs_key'.tr(),
                VaultStatus.pendingApproval => 'vault.pending'.tr(),
                VaultStatus.signedOut => '',
              }),
            ),
          );
          rows
            ..add(const AppRowDivider(indent: 58))
            ..add(
              AppListTile(
                leading: const Glyph(AppIcons.close),
                title: Text('vault.sign_out'.tr()),
                onTap: _busy ? null : _account.signOut,
              ),
            );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader('vault.title'.tr()),
            AppGroup(child: Column(children: rows)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                child: Text(_error!, style: muted),
              ),
          ],
        );
      },
    );
  }
}
