import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/ui/app_ui.dart';

/// Records a short voice message and returns the temp file path (or null if
/// cancelled / permission denied). Presented as a frosted-glass sheet.
Future<String?> showVoiceRecorder(BuildContext context) => showAppSheet<String>(
  context,
  icon: AppIcons.mic,
  iconColor: const Color(0xFFFF2D55),
  title: 'send.voice_message'.tr(),
  dismissible: false,
  builder: (ctx) => _VoiceBody(onDone: (path) => Navigator.pop(ctx, path)),
);

class _VoiceBody extends StatefulWidget {
  const _VoiceBody({required this.onDone});
  final ValueChanged<String?> onDone;

  @override
  State<_VoiceBody> createState() => _VoiceBodyState();
}

class _VoiceBodyState extends State<_VoiceBody> {
  final _rec = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  bool _denied = false;
  bool _kept = false;
  String? _path;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'voice-${const Uuid().v4().substring(0, 8)}.m4a',
      );
      await _rec.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _path = path;
      if (!mounted) return;
      setState(() => _recording = true);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _seconds++),
      );
    } on Object {
      // Recording backend unavailable (no mic / missing encoder on some
      // desktops). Surface the denied UI instead of an unhandled error.
      if (mounted) setState(() => _denied = true);
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _kept = true;
    final path = await _rec.stop();
    widget.onDone(path ?? _path);
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_recording) await _rec.stop();
    _discardTempFile();
    widget.onDone(null);
  }

  void _discardTempFile() {
    final path = _path;
    if (path == null) return;
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!_kept) _discardTempFile(); // discard on barrier-dismiss / back
    _rec.dispose();
    super.dispose();
  }

  String get _elapsed {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    if (_denied) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'send.mic_permission'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.mutedForeground),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ShadButton.outline(
              onPressed: () => widget.onDone(null),
              child: Text('send.close'.tr()),
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _elapsed,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: cs.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _recording ? 'send.recording'.tr() : 'send.starting'.tr(),
          style: TextStyle(color: cs.mutedForeground),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                onPressed: _cancel,
                child: Text('send.cancel'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ShadButton(
                onPressed: _recording ? _finish : null,
                leading: const AppSvgIcon(AppIcons.check, size: 18),
                child: Text('send.stop_and_add'.tr()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
