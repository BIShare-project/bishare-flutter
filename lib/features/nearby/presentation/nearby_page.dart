import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
    final cs = ShadTheme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: cs.background,
      body: Stack(
        children: [
          // Ambient top glow for depth.
          Positioned(
            top: -140,
            left: 0,
            right: 0,
            height: 360,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [
                    cs.primary.withValues(alpha: isDark ? 0.18 : 0.10),
                    cs.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
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

/// A glass pill showing the live search status with a breathing dot.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final searching = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: cs.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.border),
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
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: cs.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

/// A softly pulsing accent dot.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ShadTheme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.3 + 0.5 * _c.value),
              blurRadius: 3 + 5 * _c.value,
              spreadRadius: _c.value,
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass transfer card with a mini progress ring.
class _TransferCard extends StatelessWidget {
  const _TransferCard({super.key, required this.state});
  final NearbyState state;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final sending = state.direction == 'send';
    final pct = (state.progress * 100).clamp(0, 100).toInt();
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.card.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
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
                  backgroundColor: cs.muted,
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
                AppSvgIcon(
                  sending ? AppIcons.uploadFile : AppIcons.downloadFile,
                  size: 16,
                  color: cs.primary,
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
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: cs.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state.fileName ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$pct%',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}
