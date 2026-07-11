import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../../settings/domain/settings.dart';
import '../../../settings/presentation/settings_cubit.dart';

/// The privacy indicator + quick pause at the top of the Clipboard history
/// page: shows whether clipboard sync is currently active and toggles it
/// (same setting as Settings → Sync → Universal clipboard).
class ClipboardSyncToggle extends StatelessWidget {
  const ClipboardSyncToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return BlocBuilder<SettingsCubit, Settings>(
      buildWhen: (a, b) => a.clipboardSync != b.clipboardSync,
      builder: (context, settings) {
        final on = settings.clipboardSync;
        return AppGroup(
          child: AppListTile(
            leading: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: on
                    ? cs.primary.withValues(alpha: 0.12)
                    : cs.muted,
                borderRadius: BorderRadius.circular(9),
              ),
              child: AppSvgIcon(
                AppIcons.clipboard,
                size: 20,
                color: on ? cs.primary : cs.mutedForeground,
              ),
            ),
            title: Text('settings.universal_clipboard'.tr()),
            subtitle: Text(
              on ? 'clipboard.sync_active'.tr() : 'clipboard.sync_paused'.tr(),
            ),
            trailing: ShadSwitch(
              value: on,
              onChanged: (v) =>
                  context.read<SettingsCubit>().setClipboardSync(v),
            ),
          ),
        );
      },
    );
  }
}
