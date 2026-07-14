import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../data/oauth_service.dart';
import 'auth_cubit.dart';

/// The magic-link sign-in screen — a two-step flow (email → 6-char code) built
/// entirely from the design-system kit so it reads as one language with the rest
/// of the app. Below the email step sit the OAuth shortcuts: Google on
/// Android/iOS/macOS and Apple on iOS/macOS (see [OauthService]).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _submitEmail(AuthCubit cubit) =>
      cubit.requestCode(_emailCtrl.text);

  void _submitCode(AuthCubit cubit) => cubit.verifyCode(_codeCtrl.text);

  /// Dismiss the (autofocused) email field's keyboard before launching a native
  /// OAuth sheet, so it doesn't reappear behind the provider UI or linger after.
  void _oauth(BuildContext context, Future<void> Function() run) {
    FocusScope.of(context).unfocus();
    run();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocConsumer<AuthCubit, AuthState>(
          listenWhen: (prev, curr) =>
              prev.status != curr.status || prev.email != curr.email,
          listener: (context, state) {
            // Sign-in complete — greet and return to wherever they came from.
            if (state.status == AuthStatus.authenticated) {
              // Drop focus so the (autofocused) field's keyboard doesn't linger
              // on the screen we pop back to.
              FocusScope.of(context).unfocus();
              toast(
                context,
                'auth.welcome'.tr(namedArgs: {'email': state.user?.email ?? ''}),
                type: ToastType.success,
              );
              Navigator.of(context).maybePop();
            }
            // Reset the code field whenever the step changes.
            if (state.status != AuthStatus.codeSent) _codeCtrl.clear();
          },
          builder: (context, state) {
            final cubit = context.read<AuthCubit>();
            final onCodeStep = state.status == AuthStatus.codeSent;
            return AppResponsivePane(
              maxWidth: 480,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: 'auth.title'.tr(),
                    subtitle: 'auth.subtitle'.tr(),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      children: onCodeStep
                          ? _codeStep(context, cubit, state)
                          : _emailStep(context, cubit, state),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---- Step 1: email ----
  List<Widget> _emailStep(
    BuildContext context,
    AuthCubit cubit,
    AuthState state,
  ) {
    return [
      _hero(
        context,
        icon: AppIcons.logIn,
        title: 'auth.email_hero_title'.tr(),
        message: 'auth.email_intro'.tr(),
      ),
      const SizedBox(height: 18),
      _fieldLabel(context, 'auth.email_label'.tr()),
      const SizedBox(height: 7),
      ShadInput(
        controller: _emailCtrl,
        autofocus: true,
        enabled: !state.submitting,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        placeholder: Text('auth.email_hint'.tr()),
        leading: const AppSvgIcon(AppIcons.mailSend, size: 16),
        onChanged: (_) => cubit.clearError(),
        onSubmitted: (_) => _submitEmail(cubit),
      ),
      _errorText(context, state.errorKey),
      const SizedBox(height: 16),
      AppButton(
        label: 'auth.send_code'.tr(),
        icon: AppIcons.mailSend,
        fullWidth: true,
        loading: state.submitting,
        onPressed: () => _submitEmail(cubit),
      ),
      // OAuth shortcuts — same session path as the code flow (AuthCubit).
      if (OauthService.googleAvailable || OauthService.appleAvailable) ...[
        const SizedBox(height: 18),
        _orDivider(context),
        const SizedBox(height: 18),
        if (OauthService.googleAvailable)
          AppButton(
            label: 'auth.continue_google'.tr(),
            variant: AppButtonVariant.outline,
            fullWidth: true,
            disabled: state.submitting,
            onPressed: () => _oauth(context, cubit.signInWithGoogle),
          ),
        if (OauthService.appleAvailable) ...[
          const SizedBox(height: 10),
          AppButton(
            label: 'auth.continue_apple'.tr(),
            variant: AppButtonVariant.outline,
            fullWidth: true,
            disabled: state.submitting,
            onPressed: () => _oauth(context, cubit.signInWithApple),
          ),
        ],
      ],
    ];
  }

  // ---- Step 2: code ----
  List<Widget> _codeStep(
    BuildContext context,
    AuthCubit cubit,
    AuthState state,
  ) {
    return [
      // The design-system "code sent" confirmation.
      AppEmptyState(
        icon: AppIcons.mailSend,
        title: 'auth.code_sent_title'.tr(),
        message: 'auth.code_sent_message'.tr(
          namedArgs: {'email': state.email},
        ),
      ),
      const SizedBox(height: 4),
      _fieldLabel(context, 'auth.code_label'.tr()),
      const SizedBox(height: 7),
      ShadInput(
        controller: _codeCtrl,
        autofocus: true,
        enabled: !state.submitting,
        maxLength: 6,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.done,
        inputFormatters: [_UpperCaseFormatter()],
        placeholder: Text('auth.code_hint'.tr()),
        leading: const AppSvgIcon(AppIcons.passwordLock, size: 16),
        onChanged: (_) => cubit.clearError(),
        onSubmitted: (_) => _submitCode(cubit),
      ),
      _errorText(context, state.errorKey),
      const SizedBox(height: 16),
      AppButton(
        label: 'auth.verify'.tr(),
        icon: AppIcons.verifiedCheck,
        fullWidth: true,
        loading: state.submitting,
        onPressed: () => _submitCode(cubit),
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppButton(
            label: 'auth.resend'.tr(),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            onPressed: state.submitting ? null : cubit.resendCode,
          ),
          AppButton(
            label: 'auth.change_email'.tr(),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            onPressed: state.submitting ? null : cubit.backToEmail,
          ),
        ],
      ),
    ];
  }

  // ---- shared bits ----

  /// The "or" separator between the email flow and the OAuth shortcuts.
  Widget _orDivider(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: cs.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'auth.or_continue'.tr().toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: cs.mutedForeground,
            ),
          ),
        ),
        Expanded(child: Divider(color: cs.border, height: 1)),
      ],
    );
  }

  Widget _hero(
    BuildContext context, {
    required String icon,
    required String title,
    required String message,
  }) {
    final cs = ShadTheme.of(context).colorScheme;
    return AppCard(
      gradient: true,
      margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: AppSvgIcon(icon, size: 24, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: cs.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(BuildContext context, String text) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: cs.mutedForeground,
        ),
      ),
    );
  }

  Widget _errorText(BuildContext context, String? errorKey) {
    if (errorKey == null) return const SizedBox.shrink();
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSvgIcon(AppIcons.circleAlert, size: 15, color: cs.destructive),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              errorKey.tr(),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: cs.destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uppercases the verification code as the user types (the server compares it
/// case-sensitively against an UPPERCASE code).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => TextEditingValue(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
    composing: TextRange.empty,
  );
}
