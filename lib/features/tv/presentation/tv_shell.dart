import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/bishare_qr.dart';
import '../../inbox/presentation/inbox_cubit.dart';
import 'widgets/tv_incoming_overlay.dart';
import 'widgets/tv_received_grid.dart';

/// Android TV shell — a receive-only, remote-navigable surface. A TV is a place
/// you send files TO (photos/video for the big screen), so there is no send /
/// scan / compose flow here. The device keeps advertising over mDNS and running
/// its receiver (started in bootstrap); this screen just presents "ready to
/// receive", an incoming accept/decline prompt, and the received-files gallery —
/// all driven by the D-pad.
class TvShell extends StatelessWidget {
  const TvShell({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final name = getIt<DeviceIdentity>().alias;

    return Scaffold(
      backgroundColor: cs.background,
      body: Stack(
        children: [
          // Main content — generous overscan-safe padding for TV bezels.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 40, 56, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(name: name),
                  const SizedBox(height: 36),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 400, child: _ReadyPanel(name: name)),
                        const SizedBox(width: 48),
                        const Expanded(child: _ReceivedPanel()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Incoming accept/decline + live progress overlay.
          const TvIncomingOverlay(),
        ],
      ),
    );
  }
}

/* ── Header ───────────────────────────────────────────────────────────────── */
class _Header extends StatelessWidget {
  const _Header({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            'B',
            style: TextStyle(
              color: cs.primaryForeground,
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          'BIShare',
          style: TextStyle(
            color: cs.foreground,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const Spacer(),
        _StatusChip(),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: cs.border),
        borderRadius: BorderRadius.circular(999),
        color: cs.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: const BoxDecoration(
              color: Color(0xFF4ADE80),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'tv.status_ready'.tr(),
            style: TextStyle(
              color: cs.mutedForeground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/* ── Ready panel (identity + how to send + invite QR) ─────────────────────── */
class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'tv.ready_to_receive'.tr(),
          style: TextStyle(
            color: cs.mutedForeground,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: TextStyle(
            color: cs.foreground,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'tv.how_to_send'.tr(namedArgs: {'name': name}),
          style: TextStyle(
            color: cs.mutedForeground,
            fontSize: 17,
            height: 1.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.card,
            border: Border.all(color: cs.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: const BiShareQr(data: 'https://bishare.app', size: 96),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'tv.no_app_scan'.tr(),
                  style: TextStyle(
                    color: cs.mutedForeground,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/* ── Received panel ───────────────────────────────────────────────────────── */
class _ReceivedPanel extends StatelessWidget {
  const _ReceivedPanel();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'tv.received'.tr(),
          style: TextStyle(
            color: cs.foreground,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: BlocBuilder<InboxCubit, List<TransferRecord>>(
            builder: (context, items) {
              final received = items
                  .where((r) => r.savedPath != null)
                  .toList(growable: false);
              if (received.isEmpty) return const _EmptyReceived();
              return TvReceivedGrid(items: received);
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyReceived extends StatelessWidget {
  const _EmptyReceived();

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: cs.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: cs.mutedForeground),
            const SizedBox(height: 16),
            Text(
              'tv.empty_received'.tr(),
              style: TextStyle(color: cs.mutedForeground, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
