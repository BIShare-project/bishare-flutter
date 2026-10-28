import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../data/vault_account.dart';
import '../data/vault_api.dart';
import '../data/vault_signin.dart';
import 'vault_desktop_pairing.dart';

/// "Continue with Google" and "Continue with Apple", where the platform has
/// them, with the error under the buttons; on Windows and Linux, which have
/// no sign-in, "Connect with your phone" instead. Used in Settings and in
/// Drive.
class VaultSignInButtons extends StatefulWidget {
  const VaultSignInButtons({super.key});

  @override
  State<VaultSignInButtons> createState() => _VaultSignInButtonsState();
}

class _VaultSignInButtonsState extends State<VaultSignInButtons> {
  final VaultAccount _account = getIt<VaultAccount>();
  bool _busy = false;
  String? _error;

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
    } on Object catch (e) {
      // The keychain or a provider's own error (audit P15): still a message,
      // not a button that silently stops.
      _error = 'vault.error_generic'.tr();
      debugPrint('[vault] sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final muted = AppType.secondary.copyWith(color: t.text2);
    if (VaultSignin.byApproval) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: AppButton(
          label: 'vault.pair_connect'.tr(),
          icon: AppIcons.qrShare,
          fullWidth: true,
          onPressed: () => unawaited(showVaultDesktopPairing(context)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (VaultSignin.googleAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppButton(
              label: 'vault.sign_in_google'.tr(),
              // Equal to Apple's: App Store rule 4.8.
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.large,
              fullWidth: true,
              loading: _busy,
              onPressed: _busy ? null : () => _signIn('google'),
            ),
          ),
        if (VaultSignin.appleAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppButton(
              label: 'vault.sign_in_apple'.tr(),
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.large,
              fullWidth: true,
              loading: _busy,
              onPressed: _busy ? null : () => _signIn('apple'),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: muted, textAlign: TextAlign.center),
          ),
        // A Drive made on another device opens with the same sign-in: the
        // phrase is asked for only after it, when the key copy is not there.
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'vault.sign_in_hint'.tr(),
            style: muted.copyWith(height: 1.4),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
