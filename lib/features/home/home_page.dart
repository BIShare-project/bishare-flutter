import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/desktop/desktop_service.dart';
import '../../core/ui/app_showcase.dart';
import '../../core/ui/shell_tab.dart';
import '../../core/ui/app_ui.dart';
import '../receive/presentation/incoming_file_request_sheet.dart';
import '../receive/presentation/incoming_transfer_sheet.dart';
import '../receive/presentation/receive_cubit.dart';
import '../send/data/send_media_library.dart';
import '../send/presentation/send_cubit.dart';
import '../send/presentation/send_selection_cubit.dart';
import '../send/presentation/tray_cubit.dart';
import 'widgets/send_desktop_pane.dart';
import 'widgets/send_header.dart';
import 'widgets/send_list_tabs.dart';
import 'widgets/send_media_tab.dart';
import 'widgets/send_selection_bar.dart';

/// The Send tab (redesign-plan.md phase 3). On phones and tablets: the
/// header, the library tabs (Photos, Videos, Audio, Apps on Android,
/// Documents, More), the selection bar and the send sheet. On computers: a
/// drop zone with the destinations beside it. It also carries the incoming
/// prompts, whatever screen is on.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: DropTarget(
        // Desktop drag-drop: dropped files/folders join the staging tray.
        // Only while Home is on screen: the tabs share one window, and a
        // drop on Drive must not land here too.
        enable: ShellTab.isActive(context),
        onDragDone: (detail) => context.read<TrayCubit>().addDropped(
          detail.files.map((f) => f.path).toList(),
        ),
        child: SafeArea(
          child: MultiBlocListener(
            listeners: [
              BlocListener<ReceiveCubit, ReceiveState>(
                listenWhen: (p, c) =>
                    c.pending != null && p.pending?.id != c.pending?.id,
                listener: _showIncomingSheet,
              ),
              BlocListener<ReceiveCubit, ReceiveState>(
                listenWhen: (p, c) =>
                    c.pendingRequest != null &&
                    p.pendingRequest?.id != c.pendingRequest?.id,
                listener: _showFileRequestSheet,
              ),
              // The floating card says what arrived (4.2); a file only taps.
              BlocListener<ReceiveCubit, ReceiveState>(
                listenWhen: (p, c) =>
                    p.lastReceived?.savedPath != c.lastReceived?.savedPath &&
                    c.lastReceived != null,
                listener: (context, s) => HapticFeedback.lightImpact(),
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
                if (isDesktop) const SendDesktopPane() else const _SendTabs(),
                // The selection bar; the shell floats live transfers above it.
                if (!isDesktop)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SendSelectionBar(),
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
    accepted ? cubit.accept(pending) : cubit.reject(pending);
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
    final t = context.tokens;
    final pin = await showAppSheet<String>(
      context,
      icon: AppIcons.passwordLock,
      iconColor: message.isNotEmpty ? t.danger : null,
      title: 'home.pin_required'.tr(),
      subtitle: message.isNotEmpty
          ? message
          : 'home.device_protected_pin'.tr(namedArgs: {'alias': alias}),
      builder: (ctx) {
        void submit() => Navigator.pop(ctx, controller.text);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Six boxes for the PIN Settings sets now; up to 8 still go in
            // for a PIN set by an older version.
            AppCodeBoxes(
              controller: controller,
              length: 6,
              maxLength: 8,
              digits: true,
              obscure: true,
              error: message.isNotEmpty,
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

/// The library tabs of the Send tab.
class _SendTabs extends StatelessWidget {
  const _SendTabs();

  @override
  Widget build(BuildContext context) {
    final android = Platform.isAndroid;
    final tabs = <(String, SendKind?, Widget)>[
      (
        'home.photos'.tr(),
        SendKind.photo,
        const SendMediaTab(kind: SendMediaKind.photo),
      ),
      (
        'compose.tab_video'.tr(),
        SendKind.video,
        const SendMediaTab(kind: SendMediaKind.video),
      ),
      ('compose.tab_audio'.tr(), SendKind.audio, const SendAudioTab()),
      if (android) ('home.apps'.tr(), SendKind.app, const SendAppsTab()),
      ('compose.tab_documents'.tr(), SendKind.doc, const SendDocsTab()),
      ('compose.tab_more'.tr(), SendKind.more, const SendMoreTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          const SendHeader(),
          AppShowcase(
            showcaseKey: ShowcaseKeys.homeTray,
            title: 'showcase.home_tray_title'.tr(),
            description: 'showcase.home_tray_body'.tr(),
            targetRadius: 0,
            child: BlocBuilder<SendSelectionCubit, SendSelection>(
              buildWhen: (a, b) => a.length != b.length,
              builder: (context, s) => AppTabBar(
                tabs: [
                  for (final (label, kind, _) in tabs)
                    AppTab(label, count: kind == null ? 0 : s.countOf(kind)),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [for (final (_, _, page) in tabs) page],
            ),
          ),
        ],
      ),
    );
  }
}
