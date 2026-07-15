import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/config/feature_flags.dart';
import '../../../../core/di/locator.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../auth/presentation/auth_cubit.dart';
import 'glyph.dart';

/// The Settings "Account" block: a Sign-in row when signed out, or the
/// signed-in identity (name · email · tier badge) with a sign-out sheet when
/// signed in. Reads the app-wide [AuthCubit], so the same state also feeds the
/// future Drive tab.
///
/// Launch flag: while `login_enabled` is off (admin-controlled), a signed-out
/// device shows no Account section at all — sign-in simply doesn't exist yet.
/// An existing session keeps its profile row (sign-out still works).
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        return ListenableBuilder(
          listenable: getIt<FeatureFlags>(),
          builder: (context, _) {
            if (!state.isAuthenticated && !getIt<FeatureFlags>().loginEnabled) {
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                AppSectionHeader('auth.account'.tr()),
                AppGroup(
                  child: state.isAuthenticated
                      ? _signedIn(context, cs, state)
                      : _signedOut(context, cs),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _signedOut(BuildContext context, ShadColorScheme cs) => AppListTile(
    leading: const Glyph(AppIcons.logIn),
    title: Text('auth.sign_in'.tr()),
    subtitle: Text('auth.sign_in_subtitle'.tr()),
    trailing: _chevron(cs),
    onTap: () => context.push('/login'),
  );

  Widget _signedIn(BuildContext context, ShadColorScheme cs, AuthState state) {
    final user = state.user!;
    final name = user.name.isNotEmpty ? user.name : user.email;
    return AppListTile(
      leading: const Glyph(AppIcons.user),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        user.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBadge(state.tier.toUpperCase()),
          const SizedBox(width: 8),
          _chevron(cs),
        ],
      ),
      onTap: () => _confirmSignOut(context),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final cubit = context.read<AuthCubit>();
    final confirmed = await showAppSheet<bool>(
      context,
      icon: AppIcons.logIn,
      title: 'auth.sign_out_confirm'.tr(),
      subtitle: 'auth.sign_out_message'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSheetAction(
            icon: AppIcons.logIn,
            label: 'auth.sign_out'.tr(),
            destructive: true,
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await cubit.logout();
    if (context.mounted) {
      toast(context, 'auth.signed_out'.tr(), type: ToastType.success);
    }
  }

  static Widget _chevron(ShadColorScheme cs) => AppSvgIcon(
    AppIcons.chevronRight,
    size: 18,
    color: cs.mutedForeground.withValues(alpha: 0.6),
  );
}
