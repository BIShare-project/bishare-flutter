import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_ui.dart';
import '../../../core/ui/shell_tab.dart';
import '../../receive/presentation/receive_cubit.dart';
import '../../send/presentation/send_cubit.dart';
import '../../send/presentation/send_selection_cubit.dart';
import 'transfer_card.dart';

/// The live transfer cards above the bottom bar, on every tab (redesign-plan.md
/// 4.2): receiving above sending. A finished receive stays a few seconds with
/// "View"; one that stopped part way stays until closed. On the Send tab the
/// cards sit above the selection bar. Renders nothing when idle, so taps reach
/// the screen underneath.
class FloatingTransfers extends StatelessWidget {
  const FloatingTransfers({super.key, required this.onSendTab});

  /// The Send tab is showing, so the selection bar may be under the cards.
  final bool onSendTab;

  @override
  Widget build(BuildContext context) {
    final wide = context.isWideLayout;
    final cards = Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [_ReceiveCard(), _SendCard()],
      ),
    );
    if (wide) {
      return SafeArea(
        top: false,
        child: Align(
          alignment: AlignmentDirectional.bottomEnd,
          child: SizedBox(width: 420, child: cards),
        ),
      );
    }
    if (!onSendTab) return cards;
    return BlocSelector<SendSelectionCubit, SendSelection, bool>(
      selector: (s) => s.isNotEmpty,
      builder: (context, selecting) => Padding(
        // The selection bar is 66 tall with its margin.
        padding: EdgeInsets.only(bottom: selecting ? 66 : 0),
        child: cards,
      ),
    );
  }
}

/// Opens the Inbox tab.
void _openInbox() => shellTabRequest.value = ShellTabId.inbox;

String _progressLine({
  required String first,
  required double fraction,
  required double speed,
  double? eta,
}) => [
  first,
  '${(fraction * 100).clamp(0, 100).toInt()}%',
  if (speed > 0) fmtSpeed(speed),
  if (speed > 0 && eta != null) fmtEta(eta),
].join(' · ');

class _ReceiveCard extends StatefulWidget {
  const _ReceiveCard();

  @override
  State<_ReceiveCard> createState() => _ReceiveCardState();
}

class _ReceiveCardState extends State<_ReceiveCard> {
  /// The finished receive still on screen.
  ReceiveOutcome? _ended;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _show(ReceiveOutcome o) {
    _hide?.cancel();
    setState(() => _ended = o);
    // A full success fades on its own; a partial one waits to be read.
    if (o.complete) {
      _hide = Timer(const Duration(seconds: 6), _dismiss);
    }
  }

  void _dismiss() {
    _hide?.cancel();
    if (mounted) setState(() => _ended = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BlocConsumer<ReceiveCubit, ReceiveState>(
      listenWhen: (p, c) =>
          c.outcome != null && p.outcome?.sessionId != c.outcome?.sessionId,
      listener: (context, s) => _show(s.outcome!),
      buildWhen: (p, c) =>
          p.progress?.bytesReceived != c.progress?.bytesReceived ||
          (p.progress == null) != (c.progress == null) ||
          p.outcome?.sessionId != c.outcome?.sessionId,
      builder: (context, s) {
        final p = s.progress;
        if (p != null) {
          return TransferCard(
            icon: AppIcons.downloadFile,
            tone: t.receive,
            title: 'home.receiving_from'.tr(
              namedArgs: {'alias': p.senderAlias},
            ),
            subtitle: _progressLine(
              first: p.totalFiles > 1
                  ? 'receive.files_of'.tr(
                      namedArgs: {
                        'done': '${p.completedFiles}',
                        'total': '${p.totalFiles}',
                      },
                    )
                  : (p.currentFileName.isEmpty
                        ? 'home.starting'.tr()
                        : p.currentFileName),
              fraction: p.fraction,
              speed: s.speed,
              eta: s.etaSeconds,
            ),
            badge: p.transport,
            fraction: p.fraction,
          );
        }
        final o = _ended;
        if (o == null) return const SizedBox.shrink();
        final view = (
          'receive.view'.tr(),
          () {
            _dismiss();
            _openInbox();
          },
        );
        if (o.complete) {
          // Receive tone, so "View" reads in the receive colour too.
          return ReceiveTone(
            child: TransferCard(
              icon: AppIcons.check,
              tone: t.receiveStrong,
              filled: true,
              title: 'receive.done_title'.plural(o.total),
              subtitle: 'receive.done_from'.tr(
                namedArgs: {
                  'alias': o.senderAlias,
                  'size': formatBytes(o.bytes),
                },
              ),
              action: view,
              onClose: _dismiss,
            ),
          );
        }
        return TransferCard(
          icon: AppIcons.circleAlert,
          tone: t.danger,
          title: 'receive.stopped_title'.tr(),
          subtitle: [
            o.senderAlias,
            'receive.saved_of'.tr(
              namedArgs: {'saved': '${o.saved}', 'total': '${o.total}'},
            ),
          ].join(' · '),
          action: o.saved > 0 ? view : null,
          onClose: _dismiss,
        );
      },
    );
  }
}

class _SendCard extends StatelessWidget {
  const _SendCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BlocBuilder<SendCubit, SendState>(
      builder: (context, s) {
        final cubit = context.read<SendCubit>();
        if (s.status == SendStatus.sending) {
          return TransferCard(
            icon: AppIcons.uploadFile,
            title: 'home.sending_to'.tr(namedArgs: {'alias': s.deviceAlias}),
            subtitle: _progressLine(
              first: s.fileName.isEmpty ? 'home.preparing'.tr() : s.fileName,
              fraction: s.fraction,
              speed: s.speed,
              eta: s.etaSeconds,
            ),
            badge: s.transport,
            fraction: s.fraction,
            onClose: cubit.cancel,
            closeTooltip: 'common.cancel'.tr(),
          );
        }
        if (s.status == SendStatus.error) {
          return TransferCard(
            icon: AppIcons.circleAlert,
            tone: t.danger,
            title: 'receive.failed_to_send'.tr(
              namedArgs: {'alias': s.deviceAlias},
            ),
            subtitle: s.message,
            action: ('home.retry'.tr(), cubit.retryLast),
            onClose: cubit.reset,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
