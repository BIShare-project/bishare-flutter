import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/ui/app_ui.dart';
import '../../inbox/presentation/inbox_cubit.dart';
import '../../receive/presentation/receive_cubit.dart';
import 'tv_file_viewer.dart';

/// Android TV shell: a receive-only, remote-navigable surface. A TV is a
/// place you send files TO (photos/video for the big screen), so there is
/// no send / scan / compose flow here. The device keeps advertising over
/// mDNS and running its receiver (started in bootstrap); this screen shows
/// "ready to receive" with the TV's name, the received files as a big
/// grid, and the incoming prompt on top, all driven by the D-pad. Incoming
/// files take the receive colour.
class TvShell extends StatelessWidget {
  const TvShell({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = getIt<DeviceIdentity>().alias;
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          // Generous overscan-safe padding for TV bezels.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(56, 36, 56, 28),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 380, child: _ReadyPanel(name: name)),
                  const SizedBox(width: 56),
                  const Expanded(child: _ReceivedPanel()),
                ],
              ),
            ),
          ),
          const _IncomingLayer(),
        ],
      ),
    );
  }
}

/* ── Ready: the name, how to send, the QR for people without the app ───── */

class _ReadyPanel extends StatelessWidget {
  const _ReadyPanel({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Scroll-safe: TV logical heights are short (high DPR) and device names
    // can be long, so this panel flows top-down and scrolls.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BIShare',
            style: AppType.title.copyWith(fontSize: 22, color: t.text2),
          ),
          const SizedBox(height: 28),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.title.copyWith(
              fontSize: 40,
              height: 1.1,
              color: t.text,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: t.ok, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'tv.ready_to_receive'.tr(),
                  style: AppType.body.copyWith(fontSize: 20, color: t.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'tv.how_to_send'.tr(namedArgs: {'name': name}),
            style: AppType.body.copyWith(
              fontSize: 18,
              height: 1.45,
              color: t.text2,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // White under the code in both themes, so a phone reads it.
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const BiShareQr(data: 'https://bishare.app', size: 96),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'tv.no_app_scan'.tr(),
                  style: AppType.body.copyWith(
                    fontSize: 18,
                    height: 1.4,
                    color: t.text2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ── Received: a big D-pad grid, the newest first ─────────────────────── */

class _ReceivedPanel extends StatelessWidget {
  const _ReceivedPanel();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'tv.received'.tr(),
          style: AppType.title.copyWith(fontSize: 26, color: t.text),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: BlocBuilder<InboxCubit, List<TransferRecord>>(
            builder: (context, items) {
              final received = items
                  .where((r) => r.savedPath != null)
                  .toList(growable: false);
              if (received.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppSvgIcon(
                        AppIcons.downloadFile,
                        size: 56,
                        color: t.text3,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'tv.empty_received'.tr(),
                        textAlign: TextAlign.center,
                        style: AppType.body.copyWith(
                          fontSize: 20,
                          color: t.text2,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _ReceivedGrid(items: received);
            },
          ),
        ),
      ],
    );
  }
}

/// Arrow keys move the highlight; OK opens the full-screen viewer, which
/// pages left and right with the remote.
class _ReceivedGrid extends StatelessWidget {
  const _ReceivedGrid({required this.items});

  final List<TransferRecord> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      // Room for the focused tile to grow without clipping.
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => TvFocusable(
        autofocus: i == 0,
        onSelect: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TvFileViewer(items: items, startIndex: i),
          ),
        ),
        builder: (context, focused) =>
            _Tile(record: items[i], focused: focused),
      ),
    );
  }
}

bool isImageRecord(TransferRecord r) =>
    (r.fileType?.startsWith('image/') ?? false) && r.savedPath != null;

/// The AppIcons glyph for a file that is not a picture.
String tvFileIcon(TransferRecord r) {
  final type = r.fileType ?? '';
  if (type.startsWith('video/')) return AppIcons.fileVideo;
  if (type.startsWith('audio/')) return AppIcons.fileAudio;
  return AppIcons.fileDocument;
}

/// A received file: the picture edge to edge, or its glyph and name. The
/// focused tile grows a little and takes a receive-coloured ring.
class _Tile extends StatelessWidget {
  const _Tile({required this.record, required this.focused});

  final TransferRecord record;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isVideo = record.fileType?.startsWith('video/') ?? false;
    return AnimatedScale(
      scale: focused ? 1.05 : 1.0,
      duration: AppMotion.select,
      curve: AppMotion.standard,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: focused ? t.receive : t.line,
            width: focused ? 3 : 1,
          ),
        ),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: isImageRecord(record)
            ? Image.file(
                File(record.savedPath!),
                fit: BoxFit.cover,
                cacheWidth: 480,
                errorBuilder: (context, error, stack) =>
                    _FileFace(record: record),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _FileFace(record: record),
                  if (isVideo)
                    Center(
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: t.scrim,
                          shape: BoxShape.circle,
                        ),
                        child: const AppSvgIcon(
                          AppIcons.play,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FileFace extends StatelessWidget {
  const _FileFace({required this.record});
  final TransferRecord record;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppSvgIcon(tvFileIcon(record), size: 44, color: t.text2),
          const SizedBox(height: 12),
          Text(
            record.fileName,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppType.body.copyWith(fontSize: 16, color: t.text),
          ),
        ],
      ),
    );
  }
}

/* ── Incoming: Accept / Decline, then progress ───────────────────────── */

/// The incoming layer on top of the shell: a centred Accept/Decline panel
/// (focus starts on Accept) while a transfer waits, then a progress strip
/// at the bottom while it downloads.
class _IncomingLayer extends StatelessWidget {
  const _IncomingLayer();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReceiveCubit, ReceiveState>(
      builder: (context, state) {
        if (state.pending != null) return _AcceptPrompt(state: state);
        final p = state.progress;
        if (p != null && !p.isComplete) return _ProgressStrip(state: state);
        return const SizedBox.shrink();
      },
    );
  }
}

class _AcceptPrompt extends StatelessWidget {
  const _AcceptPrompt({required this.state});
  final ReceiveState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pending = state.pending!;
    final count = pending.files.length;
    final cubit = context.read<ReceiveCubit>();
    return Container(
      color: t.scrim,
      alignment: Alignment.center,
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppAvatar(
              icon: iconForDevice(pending.sender.deviceType ?? 'mobile'),
              size: 72,
            ),
            const SizedBox(height: 20),
            Text(
              'tv.incoming_title'.tr(),
              textAlign: TextAlign.center,
              style: AppType.title.copyWith(fontSize: 28, color: t.text),
            ),
            const SizedBox(height: 10),
            Text(
              'tv.incoming_desc'.tr(
                namedArgs: {
                  'sender': pending.sender.alias,
                  'files': 'tv.n_files'.plural(count),
                  'size': formatBytes(pending.totalBytes),
                },
              ),
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(fontSize: 20, color: t.text2),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: _TvButton(
                    label: 'tv.decline'.tr(),
                    onSelect: cubit.reject,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _TvButton(
                    label: 'tv.accept'.tr(),
                    primary: true,
                    autofocus: true,
                    onSelect: cubit.accept,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A big remote button: the receive fill for Accept, sunken for Decline; the
/// focused one grows and takes a ring in the text colour.
class _TvButton extends StatelessWidget {
  const _TvButton({
    required this.label,
    required this.onSelect,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onSelect;
  final bool primary;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.04 : 1.0,
        duration: AppMotion.select,
        curve: AppMotion.standard,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? t.receive : t.sunken,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: focused ? t.text : Colors.transparent,
              width: 3,
            ),
          ),
          child: Text(
            label,
            style: AppType.row.copyWith(
              fontSize: 20,
              color: primary ? t.onReceive : t.text,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.state});
  final ReceiveState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = state.progress!;
    final speed = state.speed;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AppSvgIcon(AppIcons.downloadFile, color: t.receive, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'tv.receiving_from'.tr(
                      namedArgs: {
                        'sender': p.senderAlias,
                        'file': p.currentFileName,
                      },
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.row.copyWith(fontSize: 19, color: t.text),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${p.completedFiles}/${p.totalFiles}',
                  style: AppType.body.copyWith(fontSize: 18, color: t.text2),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: p.fraction,
                minHeight: 8,
                backgroundColor: t.sunken,
                valueColor: AlwaysStoppedAnimation<Color>(t.receive),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${(p.fraction * 100).toStringAsFixed(0)}%'
              '${speed > 0 ? '  ·  ${formatBytes(speed.round())}/s' : ''}',
              style: AppType.body.copyWith(
                fontSize: 18,
                color: t.text2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ── Focus ──────────────────────────────────────────────────────────── */

/// A D-pad-friendly focusable wrapper for TV. Arrow keys move focus between
/// siblings (Flutter's default directional traversal); the OK / center /
/// Enter button fires [onSelect] (mapped to [ActivateIntent] by the default
/// TV shortcuts). [builder] gets the current focus state so the child can
/// render a visible highlight, essential on a 10-foot UI with no cursor.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    required this.onSelect,
    this.autofocus = false,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onShowFocusHighlight: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
