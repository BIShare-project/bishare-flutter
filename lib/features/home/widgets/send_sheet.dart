import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/app_ui.dart';
import '../../../core/ui/shell_tab.dart';
import '../../discovery/domain/discovered_device.dart';
import '../../discovery/presentation/discovery_cubit.dart';
import '../../favorites/presentation/favorites_cubit.dart';
import '../../send/presentation/send_cubit.dart';
import '../../send/presentation/send_selection_cubit.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../settings/domain/settings.dart';
import '../../vault/presentation/drive/drive_actions.dart';
import '../../web_nearby/data/web_nearby_service.dart';
import '../../web_nearby/presentation/web_nearby_cubit.dart';
import 'invite_device_sheet.dart';

/// Opens "Send N items": the nearby devices as a radar, then the other ways
/// (redesign-plan.md 3.9).
Future<void> showSendSheet(BuildContext context) =>
    showGlassModal<void>(context, builder: (_) => const _SendSheet());

/// One destination on the radar: a LAN device or a browser on this network.
class _Target {
  const _Target.device(DiscoveredDevice this.device) : web = null;
  const _Target.web(WebNearbyPeer this.web) : device = null;

  final DiscoveredDevice? device;
  final WebNearbyPeer? web;

  String get key =>
      device != null ? 'd:${device!.fingerprint}' : 'w:${web!.peerId}';
  String get name => device?.alias ?? web!.alias;
  String get icon =>
      device != null ? iconForDevice(device!.deviceType) : AppIcons.globePublic;
  String get os =>
      device != null ? device!.deviceModel : 'devices.browser_subtitle'.tr();
}

enum _Phase { idle, preparing, sending, done, failed }

class _SendSheet extends StatefulWidget {
  const _SendSheet();

  @override
  State<_SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends State<_SendSheet> {
  String? _target;
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  int _count = 0;
  int? _bytes;

  @override
  void initState() {
    super.initState();
    final s = context.read<SendSelectionCubit>().state;
    _count = s.length;
    _bytes = s.bytes;
  }

  bool get _busy => _phase == _Phase.preparing || _phase == _Phase.sending;

  Future<void> _send(_Target t) async {
    if (_busy) return;
    if (_phase == _Phase.failed && _target == t.key && t.device != null) {
      setState(() => _phase = _Phase.sending);
      await context.read<SendCubit>().retryLast();
      return;
    }
    setState(() {
      _target = t.key;
      _phase = _Phase.preparing;
      _progress = 0;
    });
    final selection = context.read<SendSelectionCubit>();
    final batch = await selection.materialize();
    if (!mounted) return;
    if (batch.isEmpty) {
      setState(() => _phase = _Phase.failed);
      return;
    }
    selection.clear();
    setState(() => _phase = _Phase.sending);
    if (t.device != null) {
      await context.read<SendCubit>().sendFiles(batch, t.device!);
    } else {
      await context.read<WebNearbyCubit>().sendFiles(t.web!.peerId, [
        for (final f in batch) File(f.path),
      ]);
      if (mounted && _phase == _Phase.sending) _finish();
    }
  }

  void _finish() {
    setState(() {
      _phase = _Phase.done;
      _progress = 1;
    });
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _onSend(BuildContext context, SendState s) {
    if (_target == null || !_target!.startsWith('d:')) return;
    switch (s.status) {
      case SendStatus.sending:
        if (s.total > 0) setState(() => _progress = s.sent / s.total);
      case SendStatus.done:
        if (_phase == _Phase.sending) _finish();
      case SendStatus.error:
        if (_phase == _Phase.sending) setState(() => _phase = _Phase.failed);
      case SendStatus.idle:
      case SendStatus.pinRequired:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = _bytes;
    return BlocListener<SendCubit, SendState>(
      listener: _onSend,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'compose.send_n'.plural(_count),
                        style: AppType.sheetTitle.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (size != null) formatBytes(size),
                          'compose.e2e'.tr(),
                        ].join(' · '),
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
                AppIconButton(
                  icon: AppIcons.close,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  color: t.text2,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          AppSectionHeader('home.nearby_devices'.tr()),
          _Radar(
            target: _target,
            phase: _phase,
            progress: _progress,
            onTap: _send,
          ),
          AppSectionHeader('compose.ways'.tr()),
          const SendWays(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The nearby devices on an arc above this device, rings for distance, a
/// beam to the device being sent to (redesign-plan.md "Screens, Send").
/// Painted once per change: no looping animation.
class _Radar extends StatelessWidget {
  const _Radar({
    required this.target,
    required this.phase,
    required this.progress,
    required this.onTap,
  });

  final String? target;
  final _Phase phase;
  final double progress;
  final void Function(_Target) onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final devices = context.watch<DiscoveryCubit>().state;
    final web = context.watch<WebNearbyCubit>().state;
    final favs = context.watch<FavoritesCubit>();
    final me = context.select<SettingsCubit, Settings>((c) => c.state);
    final targets = [
      for (final d in devices) _Target.device(d),
      for (final p in web.peers) _Target.web(p),
    ];
    if (targets.isEmpty) return const _NoDevices();

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        const h = 276.0, meY = 228.0;
        final many = targets.length > 6;
        final positions = <Offset>[];
        if (!many) {
          for (var i = 0; i < targets.length; i++) {
            final a = (200 + 140 * (i + 0.5) / targets.length) * math.pi / 180;
            positions.add(
              Offset(w / 2 + w * 0.40 * math.cos(a), meY + 158 * math.sin(a)),
            );
          }
        }
        Offset? beamTo;
        final ti = targets.indexWhere((x) => x.key == target);
        if (!many && ti >= 0 && phase != _Phase.idle) beamTo = positions[ti];

        Widget node(_Target x) {
          final mine = x.key == target;
          final ring = !mine
              ? AppTransferRing.none
              : switch (phase) {
                  _Phase.preparing || _Phase.sending => AppTransferRing.running,
                  _Phase.done => AppTransferRing.done,
                  _Phase.failed => AppTransferRing.failed,
                  _Phase.idle => AppTransferRing.none,
                };
          final status = !mine
              ? x.os
              : switch (phase) {
                  _Phase.preparing => 'home.preparing'.tr(),
                  _Phase.sending => '${(progress * 100).round()}%',
                  _Phase.done => 'history.sent'.tr(),
                  _Phase.failed => 'compose.failed_tap'.tr(),
                  _Phase.idle => x.os,
                };
          final dim =
              target != null &&
              !mine &&
              phase != _Phase.idle &&
              phase != _Phase.failed;
          return Opacity(
            opacity: dim ? 0.45 : 1,
            child: SizedBox(
              width: 104,
              child: Semantics(
                button: true,
                label: '${x.name}, $status',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: dim ? null : () => onTap(x),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppDeviceAvatar(
                        icon: x.icon,
                        size: 56,
                        ring: ring,
                        progress: phase == _Phase.preparing ? 0.04 : progress,
                        favourite:
                            x.device != null &&
                            favs.isFavorite(x.device!.fingerprint),
                      ),
                      const SizedBox(height: 4),
                      _Label(
                        x.name,
                        AppType.rowStrong.copyWith(fontSize: 13, color: t.text),
                      ),
                      _Label(
                        status,
                        AppType.small.copyWith(
                          fontWeight: FontWeight.w400,
                          fontSize: 11.5,
                          color: mine && phase == _Phase.failed
                              ? t.danger
                              : t.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (many) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              runSpacing: 10,
              children: [for (final x in targets) node(x)],
            ),
          );
        }
        return SizedBox(
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _RadarPainter(
                      me: Offset(w / 2, meY),
                      rx: w * 0.2,
                      ring: t.text3.withValues(alpha: 0.28),
                      beamTo: beamTo,
                      beam: phase == _Phase.failed ? null : t.brandLine,
                      failed: phase == _Phase.failed ? t.danger : null,
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < targets.length; i++)
                Positioned(
                  left: positions[i].dx - 52,
                  top: positions[i].dy - 36,
                  child: node(targets[i]),
                ),
              Positioned(
                left: w / 2 - 60,
                top: meY - 28,
                width: 120,
                child: Column(
                  children: [
                    AppDeviceAvatar(
                      icon: AppIcons.smartphone,
                      size: 44,
                      highlight: true,
                    ),
                    _Label(me.alias, AppType.small.copyWith(color: t.text2)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.style);
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: context.tokens.raised,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: style,
    ),
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.me,
    required this.rx,
    required this.ring,
    this.beamTo,
    this.beam,
    this.failed,
  });

  final Offset me;
  final double rx;
  final Color ring;
  final Offset? beamTo;
  final Gradient? beam;
  final Color? failed;

  @override
  void paint(Canvas canvas, Size size) {
    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = ring;
    for (var k = 1; k <= 3; k++) {
      canvas.drawOval(
        Rect.fromCenter(center: me, width: rx * 2 * k, height: 158.0 * k),
        rings,
      );
    }
    final to = beamTo;
    if (to == null) return;
    final from = me.translate(0, -26);
    final end = to.translate(0, 30);
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        (from.dx + end.dx) / 2,
        (from.dy + end.dy) / 2 - 28,
        end.dx,
        end.dy,
      );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    if (failed != null) {
      p.color = failed!;
    } else {
      p.shader = beam!.createShader(Rect.fromPoints(from, end));
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.beamTo != beamTo ||
      old.failed != failed ||
      old.ring != ring ||
      old.me != me ||
      old.rx != rx;
}

/// No device on this network yet: invite one, search again.
class _NoDevices extends StatelessWidget {
  const _NoDevices();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'compose.no_devices_title'.tr(),
            style: AppType.rowStrong.copyWith(color: t.text),
          ),
          const SizedBox(height: 4),
          Text(
            'compose.no_devices_body'.tr(),
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppButton(
                label: 'home.invite_device'.tr(),
                icon: AppIcons.inviteUser,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
                onPressed: () => showInviteDeviceSheet(context),
              ),
              AppButton(
                label: 'compose.search_again'.tr(),
                icon: AppIcons.refreshSync,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.small,
                onPressed: () => context.read<DiscoveryCubit>().restart(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The ways that are not a nearby device (used by the send sheet and the
/// desktop pane): Secure Link, QR Beam, Rooms, Save to Drive, and Nearby
/// without Wi-Fi on Apple devices. Each opens the existing flow.
class SendWays extends StatelessWidget {
  const SendWays({super.key, this.inSheet = true});

  final bool inSheet;

  Future<void> _link(BuildContext context) async {
    final batch = await context.read<SendSelectionCubit>().materialize();
    if (!context.mounted) return;
    if (inSheet) Navigator.of(context).maybePop();
    // One file goes straight to the link page; with none or several the page
    // lets the person choose, as before.
    unawaited(
      context.push(
        '/remote',
        extra: batch.length == 1 ? batch.first.path : null,
      ),
    );
  }

  Future<void> _drive(BuildContext context) async {
    final selection = context.read<SendSelectionCubit>();
    final batch = await selection.materialize();
    if (!context.mounted || batch.isEmpty) return;
    final ok = await saveToDrive(context, [for (final f in batch) f.path]);
    if (ok) {
      selection.clear();
      if (inSheet && context.mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final apple = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    final rows = <(String, String, String, VoidCallback)>[
      (
        AppIcons.linkCopy,
        'remote.title'.tr(),
        'compose.way_link_sub'.tr(),
        () => _link(context),
      ),
      (
        AppIcons.qrShare,
        'qr_beam.title'.tr(),
        'compose.way_qr_sub'.tr(),
        () {
          if (inSheet) Navigator.of(context).maybePop();
          context.push('/qr-beam/send');
        },
      ),
      (
        AppIcons.teamGroup,
        'room.title'.tr(),
        'compose.way_room_sub'.tr(),
        () {
          if (inSheet) Navigator.of(context).maybePop();
          shellTabRequest.value = ShellTabId.rooms;
        },
      ),
      if (driveReady)
        (
          AppIcons.cloudSync,
          'vault.save_to_drive'.tr(),
          'compose.way_drive_sub'.tr(),
          () => _drive(context),
        ),
      if (apple)
        (
          AppIcons.wifi,
          'compose.way_nearby'.tr(),
          'compose.way_nearby_sub'.tr(),
          () {
            if (inSheet) Navigator.of(context).maybePop();
            context.push('/nearby');
          },
        ),
    ];
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const AppRowDivider(indent: 52),
          AppValueRow(
            icon: rows[i].$1,
            title: rows[i].$2,
            subtitle: rows[i].$3,
            onTap: rows[i].$4,
          ),
        ],
      ],
    );
  }
}
