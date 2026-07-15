import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/config/feature_flags.dart';
import '../../core/di/locator.dart';
import '../../core/identity/device_identity.dart';
import '../../core/ui/app_ui.dart';
import '../receive/presentation/incoming_file_request_sheet.dart';
import '../receive/presentation/incoming_transfer_sheet.dart';
import '../receive/presentation/receive_cubit.dart';
import '../send/presentation/send_cubit.dart';
import '../send/presentation/tray_cubit.dart';
import '../settings/domain/settings.dart' show Settings;
import '../settings/presentation/settings_cubit.dart';
import 'widgets/compose_tray.dart';
import 'widgets/device_section.dart';
import 'widgets/drive_entry_card.dart';
import 'widgets/sync_entry_card.dart';
import 'widgets/floating_transfers.dart';
import 'widgets/header.dart';
import 'widgets/my_device_card.dart';

/// The home screen: your device, a staging tray, nearby devices (tap to send),
/// incoming accept prompts, and live send/receive progress. Prompts are premium
/// frosted-glass modal sheets — no Material dialogs. Reusable pieces live in the
/// design kit (`core/ui/app_ui.dart`) so this file stays about layout.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = getIt<DeviceIdentity>();
    final cs = ShadTheme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.background,
      body: DropTarget(
        // Desktop drag-drop: dropped files/folders join the staging tray.
        onDragDone: (detail) => context.read<TrayCubit>().addDropped(
          detail.files.map((f) => f.path).toList(),
        ),
        child: SafeArea(
          child: MultiBlocListener(
            listeners: [
              BlocListener<ReceiveCubit, ReceiveState>(
                listenWhen: (p, c) => p.pending == null && c.pending != null,
                listener: _showIncomingSheet,
              ),
              BlocListener<ReceiveCubit, ReceiveState>(
                listenWhen: (p, c) =>
                    c.pendingRequest != null &&
                    p.pendingRequest?.id != c.pendingRequest?.id,
                listener: _showFileRequestSheet,
              ),
              BlocListener<ReceiveCubit, ReceiveState>(
                listenWhen: (p, c) =>
                    p.lastReceived?.savedPath != c.lastReceived?.savedPath &&
                    c.lastReceived != null,
                listener: (context, s) {
                  HapticFeedback.lightImpact();
                  toast(
                    context,
                    'home.received_file'.tr(
                      namedArgs: {'file': s.lastReceived!.fileName},
                    ),
                    type: ToastType.success,
                  );
                },
              ),
              BlocListener<SendCubit, SendState>(
                listenWhen: (p, c) => p.status != c.status,
                listener: (context, s) {
                  if (s.status == SendStatus.done) {
                    HapticFeedback.lightImpact();
                    toast(
                      context,
                      'home.sent_to'.tr(namedArgs: {'alias': s.deviceAlias}),
                      type: ToastType.success,
                    );
                    context.read<TrayCubit>().clear();
                    context.read<SendCubit>().reset();
                  } else if (s.status == SendStatus.pinRequired) {
                    _promptPin(context, s.deviceAlias, s.message);
                  } else if (s.status == SendStatus.error) {
                    HapticFeedback.heavyImpact();
                  }
                },
              ),
            ],
            child: Stack(
              children: [
                AppResponsivePane(
                  maxWidth: 960,
                  child: Column(
                    children: [
                      const Header(),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 28),
                          children: [
                            BlocBuilder<SettingsCubit, Settings>(
                              builder: (context, settings) => MyDeviceCard(
                                alias: settings.alias,
                                deviceType: identity.deviceType,
                                hidden: settings.visibility.name == 'hidden',
                              ),
                            ),
                            // Drive is remote-flag gated (hidden pre-launch;
                            // flip `drive_enabled` from the admin Flags page).
                            ListenableBuilder(
                              listenable: getIt<FeatureFlags>(),
                              builder: (context, _) =>
                                  getIt<FeatureFlags>().driveEnabled
                                      ? const DriveEntryCard()
                                      : const SizedBox.shrink(),
                            ),
                            const SyncEntryCard(),
                            const ComposeTray(),
                            const DeviceSection(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Live transfers float above the content as glass cards, pinned
                // to the bottom of the screen.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: FloatingTransfers(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showIncomingSheet(
    BuildContext context,
    ReceiveState state,
  ) async {
    final pending = state.pending;
    if (pending == null) return;
    HapticFeedback.mediumImpact();
    final cubit = context.read<ReceiveCubit>();
    final accepted = await showIncomingTransfer(context, pending);
    accepted ? cubit.accept() : cubit.reject();
  }

  Future<void> _showFileRequestSheet(
    BuildContext context,
    ReceiveState state,
  ) async {
    final req = state.pendingRequest;
    if (req == null) return;
    HapticFeedback.mediumImpact();
    // The sheet owns the request now (it responds accept/decline itself); clear
    // it so a later rebuild doesn't re-open the prompt.
    context.read<ReceiveCubit>().clearRequest();
    await showIncomingFileRequest(context, req);
  }

  Future<void> _promptPin(
    BuildContext context,
    String alias,
    String message,
  ) async {
    final controller = TextEditingController();
    final cubit = context.read<SendCubit>();
    final cs = ShadTheme.of(context).colorScheme;
    final pin = await showAppSheet<String>(
      context,
      icon: AppIcons.passwordLock,
      iconColor: message.isNotEmpty ? cs.destructive : null,
      title: 'home.pin_required'.tr(),
      subtitle: message.isNotEmpty
          ? message
          : 'home.device_protected_pin'.tr(namedArgs: {'alias': alias}),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShadInput(
              controller: controller,
              placeholder: Text('home.enter_pin'.tr()),
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => submit(),
            ),
            const SizedBox(height: 14),
            AppButton(
              label: 'home.send'.tr(),
              icon: AppIcons.send,
              variant: AppButtonVariant.primary,
              size: AppButtonSize.medium,
              fullWidth: true,
              onPressed: submit,
            ),
          ],
        );
      },
    );
    if (pin != null && pin.isNotEmpty) {
      await cubit.submitPin(pin);
    } else {
      cubit.reset();
    }
  }
}
