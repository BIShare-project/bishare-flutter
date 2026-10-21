import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/di/locator.dart';
import '../../../core/ui/app_ui.dart';
import '../../settings/presentation/widgets/glyph.dart';
import '../data/vault_account.dart';
import 'vault_sign_in_buttons.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(_account.load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _account,
      builder: (context, _) {
        final status = _account.status;
        final rows = <Widget>[];
        if (status == VaultStatus.signedOut) {
          rows
            ..add(
              AppListTile(
                leading: const Glyph(AppIcons.passwordLock),
                title: Text('vault.title'.tr()),
                subtitle: Text('vault.signed_out'.tr()),
              ),
            )
            ..add(
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: VaultSignInButtons(),
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
                leading: const Glyph(AppIcons.settings),
                title: Text('vault.manage'.tr()),
                trailing: const _Chevron(),
                onTap: () => context.push('/drive-account'),
              ),
            );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSectionHeader('vault.title'.tr()),
            AppGroup(child: Column(children: rows)),
          ],
        );
      },
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => AppSvgIcon(
    AppIcons.chevronRight,
    size: 18,
    color: ShadTheme.of(
      context,
    ).colorScheme.mutedForeground.withValues(alpha: 0.6),
  );
}
