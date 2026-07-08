import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/l10n/app_locales.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/ui/app_ui.dart';
import '../domain/settings.dart' as s;
import 'settings_cubit.dart';
import 'widgets/about_section.dart';
import 'widgets/accent_row.dart';
import 'widgets/autostart_row.dart';
import 'widgets/glyph.dart';
import 'widgets/profile_card.dart';
import 'widgets/select_row.dart';
import 'widgets/switch_row.dart';
import 'widgets/theme_row.dart';
import 'widgets/version_footer.dart';

/// Settings tab — a premium grouped layout: a device profile hero, appearance
/// (theme + accents), sending (media quality + transport), and receiving
/// (auto-accept + visibility + PIN + save location). Option pickers are inline
/// [ShadSelect] popovers; text prompts adapt (dialog on desktop / sheet on
/// phone). Glyphs are monochrome.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: BlocBuilder<SettingsCubit, s.Settings>(
          builder: (context, state) {
            final cubit = context.read<SettingsCubit>();
            return AppResponsivePane(
              maxWidth: 720,
              child: Column(
                children: [
                  AppScreenHeader(title: 'settings.title'.tr()),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: [
                        ProfileCard(
                          alias: state.alias,
                          onTap: () => _editAlias(context, cubit, state.alias),
                        ),
                        AppSectionHeader('settings.appearance'.tr()),
                        AppGroup(
                          child: Column(
                            children: [
                              ThemeRow(
                                value: state.themeMode,
                                onChanged: cubit.setThemeMode,
                              ),
                              const AppRowDivider(indent: 58),
                              AccentRow(
                                icon: AppIcons.paintbrush,
                                label: 'settings.send_accent'.tr(),
                                selected: state.accent,
                                onChanged: cubit.setAccent,
                              ),
                              const AppRowDivider(indent: 58),
                              AccentRow(
                                icon: AppIcons.downloadFile,
                                label: 'settings.receive_accent'.tr(),
                                selected: state.receiveAccent,
                                onChanged: cubit.setReceiveAccent,
                              ),
                              const AppRowDivider(indent: 58),
                              SelectRow<Locale>(
                                icon: AppIcons.globePublic,
                                title: 'settings.language'.tr(),
                                value: context.locale,
                                values: appLocales,
                                label: localeName,
                                onChanged: (l) => context.setLocale(l),
                              ),
                            ],
                          ),
                        ),
                        AppSectionHeader('settings.sending'.tr()),
                        AppGroup(
                          child: Column(
                            children: [
                              SelectRow<s.MediaQuality>(
                                icon: AppIcons.image,
                                title: 'settings.media_quality'.tr(),
                                value: state.mediaQuality,
                                values: s.MediaQuality.values,
                                label: (q) => q.label,
                                onChanged: cubit.setMediaQuality,
                              ),
                              const AppRowDivider(indent: 58),
                              SelectRow<s.TransportMode>(
                                icon: AppIcons.zap,
                                title: 'settings.transport'.tr(),
                                value: state.transport,
                                values: s.TransportMode.values,
                                label: (t) => t.label,
                                description: (t) => t.description,
                                onChanged: cubit.setTransport,
                              ),
                            ],
                          ),
                        ),
                        // Persistent explanation of the current transport (the
                        // picker also shows every option's description on tap).
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
                          child: Text(
                            state.transport.description,
                            style: ShadTheme.of(
                              context,
                            ).textTheme.muted.copyWith(fontSize: 12),
                          ),
                        ),
                        AppSectionHeader('settings.receiving'.tr()),
                        AppGroup(
                          child: Column(
                            children: [
                              SelectRow<AutoAcceptMode>(
                                icon: AppIcons.inviteUser,
                                title: 'settings.auto_accept'.tr(),
                                value: state.autoAccept,
                                values: AutoAcceptMode.values,
                                label: _autoAcceptLabel,
                                onChanged: cubit.setAutoAccept,
                              ),
                              const AppRowDivider(indent: 58),
                              SwitchRow(
                                icon: AppIcons.eyePreview,
                                title: 'settings.visible_everyone'.tr(),
                                subtitle: 'settings.visible_subtitle'.tr(),
                                value:
                                    state.visibility == s.Visibility.everyone,
                                onChanged: (on) => cubit.setVisibility(
                                  on
                                      ? s.Visibility.everyone
                                      : s.Visibility.hidden,
                                ),
                              ),
                              const AppRowDivider(indent: 58),
                              SwitchRow(
                                icon: AppIcons.passwordLock,
                                title: 'settings.require_pin'.tr(),
                                subtitle:
                                    state.pinEnabled && state.pinCode.isNotEmpty
                                    ? 'settings.pin_is_set'.tr()
                                    : 'settings.pin_subtitle'.tr(),
                                value: state.pinEnabled,
                                onChanged: (on) => on
                                    ? _editPin(context, cubit)
                                    : cubit.setPin(enabled: false),
                              ),
                              const AppRowDivider(indent: 58),
                              AppListTile(
                                leading: const Glyph(AppIcons.folder),
                                title: Text('settings.save_location'.tr()),
                                subtitle: Text(
                                  state.saveLocation.isEmpty
                                      ? 'settings.save_default'.tr()
                                      : state.saveLocation,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: _chevron(cs),
                                onTap: () => _pickSaveLocation(context, cubit),
                              ),
                            ],
                          ),
                        ),
                        AppSectionHeader('settings.sync'.tr()),
                        AppGroup(
                          child: Column(
                            children: [
                              SwitchRow(
                                icon: AppIcons.clipboard,
                                title: 'settings.universal_clipboard'.tr(),
                                subtitle: 'settings.clipboard_subtitle'.tr(),
                                value: state.clipboardSync,
                                onChanged: cubit.setClipboardSync,
                              ),
                              // Desktop: launch BIShare automatically at login.
                              if (isDesktop) ...[
                                const AppRowDivider(indent: 58),
                                const AutostartRow(),
                              ],
                            ],
                          ),
                        ),
                        const AboutSection(),
                        const VersionFooter(),
                      ],
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

  static Widget _chevron(ShadColorScheme cs) => AppSvgIcon(
    AppIcons.chevronRight,
    size: 18,
    color: cs.mutedForeground.withValues(alpha: 0.6),
  );

  static String _autoAcceptLabel(AutoAcceptMode m) => switch (m) {
    AutoAcceptMode.alwaysAsk => 'settings.auto_ask'.tr(),
    AutoAcceptMode.acceptAll => 'settings.auto_accept_all'.tr(),
    AutoAcceptMode.favoritesOnly => 'settings.auto_favorites'.tr(),
  };

  Future<void> _pickSaveLocation(
    BuildContext context,
    SettingsCubit cubit,
  ) async {
    final canPick = cubit.canPickSaveFolder;
    final choice = await showAppSheet<String>(
      context,
      icon: AppIcons.folder,
      title: 'settings.save_location'.tr(),
      subtitle: 'settings.save_location_subtitle'.tr(),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPick)
            AppSheetAction(
              icon: AppIcons.folderOpen,
              label: 'settings.choose_folder'.tr(),
              onTap: () => Navigator.pop(ctx, 'choose'),
            ),
          if (canPick)
            AppSheetAction(
              icon: AppIcons.externalLink,
              label: 'settings.open_folder'.tr(),
              onTap: () => Navigator.pop(ctx, 'reveal'),
            ),
          AppSheetAction(
            icon: AppIcons.refreshSync,
            label: 'settings.use_default'.tr(),
            onTap: () => Navigator.pop(ctx, 'default'),
          ),
        ],
      ),
    );
    switch (choice) {
      case 'default':
        await cubit.setSaveLocation('');
      case 'choose':
        await cubit.pickSaveLocation();
      case 'reveal':
        await cubit.revealSaveLocation();
    }
  }

  Future<void> _editAlias(
    BuildContext context,
    SettingsCubit cubit,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final name = await showAppSheet<String>(
      context,
      icon: AppIcons.user,
      title: 'settings.device_name'.tr(),
      subtitle: 'settings.device_name_subtitle'.tr(),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: controller,
              autofocus: true,
              placeholder: Text('settings.device_name_hint'.tr()),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                onPressed: submit,
                child: Text('settings.save'.tr()),
              ),
            ),
          ],
        );
      },
    );
    if (name != null && name.trim().isNotEmpty) await cubit.setAlias(name);
  }

  Future<void> _editPin(BuildContext context, SettingsCubit cubit) async {
    final controller = TextEditingController();
    final code = await showAppSheet<String>(
      context,
      icon: AppIcons.passwordLock,
      title: 'settings.set_pin'.tr(),
      subtitle: 'settings.set_pin_subtitle'.tr(),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              placeholder: Text('settings.pin_hint'.tr()),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ShadButton(
                onPressed: submit,
                child: Text('settings.enable'.tr()),
              ),
            ),
          ],
        );
      },
    );
    if (code != null && code.isNotEmpty) {
      await cubit.setPin(enabled: true, code: code);
    }
  }
}
