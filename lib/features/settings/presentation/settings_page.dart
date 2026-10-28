import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop/desktop_service.dart';
import '../../../core/l10n/app_locales.dart';
import '../../../core/server/transfer_types.dart';
import '../../../core/ui/app_ui.dart';
import '../domain/settings.dart' as s;
import '../../vault/presentation/vault_section.dart';
import 'settings_cubit.dart';
import 'settings_widgets.dart';

/// Settings tab (redesign-plan.md "Pengaturan"), in the order the settings
/// are used: this device, Receiving, Sending, Drive, Devices and sync,
/// Appearance, Privacy, About, then the version. Flat rows on the kit; a
/// choice opens a sheet with every option, text prompts adapt (dialog on
/// desktop, sheet on phone).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
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
                        ..._receiving(context, state, cubit),
                        ..._sending(context, state, cubit),
                        // BIShare Drive: nothing unless vault_enabled.
                        const VaultSection(),
                        ..._devicesAndSync(context, state, cubit),
                        ..._appearance(context, state, cubit),
                        AppSectionHeader('settings.privacy'.tr()),
                        // Anonymous, aggregate-only usage telemetry so the
                        // public stats reflect LAN transfers (no PII).
                        AppSwitchRow(
                          icon: AppIcons.storageUsage,
                          title: 'settings.telemetry'.tr(),
                          subtitle: 'settings.telemetry_subtitle'.tr(),
                          value: state.telemetryEnabled,
                          onChanged: cubit.setTelemetry,
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

  static const _divider = AppRowDivider(indent: 52);

  List<Widget> _receiving(
    BuildContext context,
    s.Settings state,
    SettingsCubit cubit,
  ) => [
    AppSectionHeader('settings.receiving'.tr()),
    AppSwitchRow(
      icon: AppIcons.eyePreview,
      title: 'settings.visible_everyone'.tr(),
      subtitle: 'settings.visible_subtitle'.tr(),
      value: state.visibility == s.Visibility.everyone,
      onChanged: (on) =>
          cubit.setVisibility(on ? s.Visibility.everyone : s.Visibility.hidden),
    ),
    _divider,
    AppSelectRow<AutoAcceptMode>(
      icon: AppIcons.inviteUser,
      title: 'settings.auto_accept'.tr(),
      value: state.autoAccept,
      values: AutoAcceptMode.values,
      label: _autoAcceptLabel,
      onChanged: cubit.setAutoAccept,
    ),
    _divider,
    AppSwitchRow(
      icon: AppIcons.passwordLock,
      title: 'settings.require_pin'.tr(),
      subtitle: state.pinEnabled && state.pinCode.isNotEmpty
          ? 'settings.pin_is_set'.tr()
          : 'settings.pin_subtitle'.tr(),
      value: state.pinEnabled,
      onChanged: (on) =>
          on ? _editPin(context, cubit) : cubit.setPin(enabled: false),
    ),
    _divider,
    AppValueRow(
      icon: AppIcons.folder,
      title: 'settings.save_location'.tr(),
      // The ACTUAL folder files land in (single source of truth), not the
      // persisted base path, which is empty/stale on macOS. Fall back to
      // the default label only before the first resolve.
      subtitle: state.resolvedSaveDir.isEmpty
          ? 'settings.save_default'.tr()
          : _tidySaveDir(state.resolvedSaveDir),
      onTap: () => _pickSaveLocation(context, cubit),
    ),
    _divider,
    // Web-Share browser uploads (feature #11): allow toggle + per-upload
    // size cap.
    AppSwitchRow(
      icon: AppIcons.uploadFile,
      title: 'settings.browser_upload'.tr(),
      subtitle: 'settings.browser_upload_subtitle'.tr(),
      value: state.browserUpload,
      onChanged: cubit.setBrowserUpload,
    ),
    if (state.browserUpload) ...[
      _divider,
      AppSelectRow<int>(
        icon: AppIcons.storageUsage,
        title: 'settings.browser_upload_limit'.tr(),
        value: state.browserUploadMaxGb,
        values: s.Settings.browserUploadLimitsGb,
        label: (gb) => gb == 0
            ? 'settings.browser_upload_unlimited'.tr()
            : 'settings.browser_upload_gb'.tr(namedArgs: {'gb': '$gb'}),
        onChanged: cubit.setBrowserUploadMaxGb,
      ),
    ],
  ];

  List<Widget> _sending(
    BuildContext context,
    s.Settings state,
    SettingsCubit cubit,
  ) {
    final t = context.tokens;
    return [
      AppSectionHeader('settings.sending'.tr()),
      AppSelectRow<s.MediaQuality>(
        icon: AppIcons.image,
        title: 'settings.media_quality'.tr(),
        value: state.mediaQuality,
        values: s.MediaQuality.values,
        label: (q) => q.label,
        onChanged: cubit.setMediaQuality,
      ),
      _divider,
      AppSelectRow<s.TransportMode>(
        icon: AppIcons.zap,
        title: 'settings.transport'.tr(),
        value: state.transport,
        values: s.TransportMode.values,
        label: (m) => m.label,
        description: (m) => m.description,
        onChanged: cubit.setTransport,
      ),
      // What the current transport does (the sheet also shows every
      // option's description).
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(52, 0, 18, 4),
        child: Text(
          state.transport.description,
          style: AppType.secondary.copyWith(fontSize: 13, color: t.text2),
        ),
      ),
    ];
  }

  List<Widget> _devicesAndSync(
    BuildContext context,
    s.Settings state,
    SettingsCubit cubit,
  ) => [
    AppSectionHeader('settings.devices_sync'.tr()),
    // Devices dashboard: the full known-devices roster with presence,
    // stats, and per-device actions.
    AppValueRow(
      icon: AppIcons.smartphone,
      title: 'devices.title'.tr(),
      subtitle: 'devices.settings_subtitle'.tr(),
      onTap: () => context.push('/devices'),
    ),
    _divider,
    AppSwitchRow(
      icon: AppIcons.clipboard,
      title: 'settings.universal_clipboard'.tr(),
      subtitle: 'settings.clipboard_subtitle'.tr(),
      value: state.clipboardSync,
      onChanged: cubit.setClipboardSync,
    ),
    // Clipboard sub-options (v2.4 Universal Clipboard), only while sync
    // is on.
    if (state.clipboardSync) ...[
      if (cubit.clipboardImagesSupported) ...[
        _divider,
        AppSwitchRow(
          icon: AppIcons.image,
          title: 'settings.clipboard_images'.tr(),
          subtitle: 'settings.clipboard_images_subtitle'.tr(),
          value: state.clipboardImages,
          onChanged: cubit.setClipboardImages,
        ),
        _divider,
        AppSelectRow<int>(
          icon: AppIcons.storageUsage,
          title: 'settings.clipboard_max_size'.tr(),
          value: state.clipboardMaxSizeMb,
          values: s.Settings.clipboardSizesMb,
          label: (mb) => 'settings.clipboard_mb'.tr(namedArgs: {'mb': '$mb'}),
          onChanged: cubit.setClipboardMaxSizeMb,
        ),
      ],
      _divider,
      // Cloud relay is not shippable yet (per-device placeholder channel
      // + backend deferred), so the switch is disabled with a "coming
      // soon" hint: it must never turn the relay on (it would reconnect
      // forever). Re-enable when the Workers sync backend + account
      // pairing ship.
      AppSwitchRow(
        icon: AppIcons.cloudSync,
        title: 'settings.clipboard_cloud'.tr(),
        subtitle: 'settings.clipboard_cloud_soon'.tr(),
        value: false,
        onChanged: null,
      ),
      _divider,
      AppValueRow(
        icon: AppIcons.clipboardPaste,
        title: 'settings.clipboard_history'.tr(),
        subtitle: 'settings.clipboard_history_subtitle'.tr(),
        onTap: () => context.push('/clipboard'),
      ),
    ],
    // Desktop: launch BIShare automatically at login.
    if (isDesktop) ...[_divider, const AutostartRow()],
  ];

  List<Widget> _appearance(
    BuildContext context,
    s.Settings state,
    SettingsCubit cubit,
  ) => [
    AppSectionHeader('settings.appearance'.tr()),
    AppSelectRow<ThemeMode>(
      icon: AppIcons.sunMoon,
      title: 'settings.theme'.tr(),
      value: state.themeMode,
      values: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark],
      label: (m) => switch (m) {
        ThemeMode.system => 'settings.theme_auto'.tr(),
        ThemeMode.light => 'settings.theme_light'.tr(),
        ThemeMode.dark => 'settings.theme_dark'.tr(),
      },
      onChanged: cubit.setThemeMode,
    ),
    _divider,
    AccentRow(
      icon: AppIcons.paintbrush,
      label: 'settings.send_accent'.tr(),
      selected: state.accent,
      onChanged: cubit.setAccent,
    ),
    _divider,
    AccentRow(
      icon: AppIcons.downloadFile,
      label: 'settings.receive_accent'.tr(),
      selected: state.receiveAccent,
      onChanged: cubit.setReceiveAccent,
    ),
    _divider,
    AppSelectRow<Locale>(
      icon: AppIcons.globePublic,
      title: 'settings.language'.tr(),
      value: context.locale,
      values: appLocales,
      label: localeName,
      onChanged: (l) => context.setLocale(l),
    ),
  ];

  static String _autoAcceptLabel(AutoAcceptMode m) => switch (m) {
    AutoAcceptMode.alwaysAsk => 'settings.auto_ask'.tr(),
    AutoAcceptMode.acceptAll => 'settings.auto_accept_all'.tr(),
    AutoAcceptMode.favoritesOnly => 'settings.auto_favorites'.tr(),
  };

  /// Tidy an absolute save-dir path down to its meaningful tail (e.g.
  /// "…/Desktop/BIShare") so the row surfaces where files land — the leading
  /// container/Documents prefix is long and, under single-line ellipsis, would
  /// otherwise be all that shows before "BIShare" gets truncated. Splits on both
  /// separators so it reads the same on Windows.
  static String _tidySaveDir(String path) {
    final parts = path
        .split(RegExp(r'[\\/]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 2) return path;
    return '…/${parts[parts.length - 2]}/${parts.last}';
  }

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
            AppTextField(
              controller: controller,
              autofocus: true,
              hint: 'settings.device_name_hint'.tr(),
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'settings.save'.tr(),
              fullWidth: true,
              onPressed: submit,
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (name != null && name.trim().isNotEmpty) await cubit.setAlias(name);
  }

  /// A PIN is 4 to 8 digits; shorter is refused in the sheet.
  Future<void> _editPin(BuildContext context, SettingsCubit cubit) async {
    final controller = TextEditingController();
    String? error;
    final code = await showAppSheet<String>(
      context,
      icon: AppIcons.passwordLock,
      title: 'settings.set_pin'.tr(),
      subtitle: 'settings.set_pin_subtitle'.tr(),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void submit() {
            if (controller.text.length < 4) {
              setState(() => error = 'settings.pin_too_short'.tr());
              return;
            }
            Navigator.pop(ctx, controller.text);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: controller,
                autofocus: true,
                obscure: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 8,
                hint: 'settings.pin_hint'.tr(),
                error: error,
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
                onSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 14),
              AppButton(
                label: 'settings.enable'.tr(),
                fullWidth: true,
                onPressed: submit,
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    if (code != null && code.isNotEmpty) {
      await cubit.setPin(enabled: true, code: code);
    }
  }
}
