import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/ui/app_ui.dart';
import '../domain/nearby_peer.dart';
import 'nearby_cubit.dart';
import 'widgets/nearby_radar.dart';
import 'widgets/nearby_send_sheet.dart';

/// Offline "Nearby" transfer over MultipeerConnectivity (iOS + macOS). Advertises
/// + browses on open; tap a peer on the radar to send the current tray to it with
/// no Wi-Fi/router needed. Received files land in the same inbox/history as LAN.
class NearbyPage extends StatefulWidget {
  const NearbyPage({super.key});

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  @override
  void initState() {
    super.initState();
    context.read<NearbyCubit>().start();
  }

  @override
  void dispose() {
    context.read<NearbyCubit>().stop();
    super.dispose();
  }

  void _onTapPeer(NearbyPeer peer) {
    final cubit = context.read<NearbyCubit>();
    // Tap a peer → a "Send to {alias}" sheet with the pick sources (Photos,
    // Files, Note …) + any staged tray. No pre-staging on another screen.
    showNearbySendSheet(
      context,
      peer: peer,
      onSend: (files) {
        cubit.connect(peer);
        cubit.sendFiles(peer, files);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          SafeArea(
            child: AppResponsivePane(
              maxWidth: 640,
              child: Column(
                children: [
                  AppScreenHeader(
                    title: 'nearby.title'.tr(),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: BlocBuilder<NearbyCubit, NearbyState>(
                      builder: (context, state) {
                        if (!state.supported) {
                          return Center(
                            child: AppEmptyState(
                              icon: AppIcons.wifi,
                              title: 'nearby.unsupported_title'.tr(),
                              message: 'nearby.unsupported_message'.tr(),
                            ),
                          );
                        }
                        return Column(
                          children: [
                            const SizedBox(height: 4),
                            _StatusPill(count: state.peers.length),
                            Expanded(
                              child: NearbyRadar(
                                peers: state.peers,
                                onTapPeer: _onTapPeer,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              child: state.transferring
                                  ? _TransferCard(
                                      key: const ValueKey('xfer'),
                                      state: state,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The live search status: a dot and the count, on the sunken colour.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final searching = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LiveDot(),
          const SizedBox(width: 8),
          Text(
            searching
                ? 'nearby.searching'.tr()
                : 'nearby.devices_nearby'.plural(count),
            style: AppType.label.copyWith(color: t.text),
          ),
        ],
      ),
    );
  }
}

/// The accent dot beside the status.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> {
  // A steady dot: the old one breathed with an animated blur shadow forever.
  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.accent;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
    );
  }
}

/// The running transfer: a ring, the direction, the name and the percent.
/// Receiving takes the receive colour.
class _TransferCard extends StatelessWidget {
  const _TransferCard({super.key, required this.state});
  final NearbyState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sending = state.direction == 'send';
    final pct = (state.progress * 100).clamp(0, 100).toInt();
    final tone = sending ? t.accent : t.receive;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: state.progress == 0 ? null : state.progress,
                  strokeWidth: 3.5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: t.sunken,
                  valueColor: AlwaysStoppedAnimation(tone),
                ),
                AppSvgIcon(
                  sending ? AppIcons.uploadFile : AppIcons.downloadFile,
                  size: 16,
                  color: tone,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sending ? 'nearby.sending'.tr() : 'nearby.receiving'.tr(),
                  style: AppType.row.copyWith(color: t.text),
                ),
                const SizedBox(height: 2),
                Text(
                  state.fileName ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.secondary.copyWith(
                    fontSize: 13,
                    color: t.text2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$pct%',
            style: AppType.label.copyWith(
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
