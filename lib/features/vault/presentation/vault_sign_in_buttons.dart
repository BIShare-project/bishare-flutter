import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../data/vault_account.dart';
import '../data/vault_api.dart';
import '../data/vault_signin.dart';

/// "Continue with Google" and "Continue with Apple", where the platform has
/// them, with the error under the buttons. Used in Settings and in Drive.
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = ShadTheme.of(context).textTheme.muted.copyWith(fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (VaultSignin.googleAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AppButton(
              label: 'vault.sign_in_google'.tr(),
              variant: AppButtonVariant.outline,
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
              variant: AppButtonVariant.outline,
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
      ],
    );
  }
}
