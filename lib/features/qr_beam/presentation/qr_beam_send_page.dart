import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/ui/app_ui.dart';
import '../domain/beam_codec.dart';

/// Max payload for QR Beam. Each frame carries [_chunkBytes], about 5 KB a
/// second at 6 fps, so this is for text, keys and documents, not media.
/// Above this we refuse with a message. (Owner 2026-10-28: 300 KB.)
const int _maxBeamBytes = 300 * 1024;

/// Above this the page says a beam takes a while.
const int _warnBeamBytes = 100 * 1024;

/// Bytes per frame. 900 rather than the codec's 600: 1.5 times faster, and a
/// QR still sharp on a phone screen at the size shown. The header names the
/// chunk size, so every receiver (app and web) reads it.
const int _chunkBytes = 900;

class QrBeamSendPage extends StatefulWidget {
  const QrBeamSendPage({super.key, this.initialPath});

  /// A file already chosen on the Send tab: it beams at once, no second pick.
  final String? initialPath;

  @override
  State<QrBeamSendPage> createState() => _QrBeamSendPageState();
}

class _QrBeamSendPageState extends State<QrBeamSendPage> {
  EncodedBeam? _beam;
  int _idx = 0;
  double _fps = 6;
  Timer? _timer;
  String? _error;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final path = widget.initialPath;
    if (path != null) unawaited(_beamFile(File(path)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// A file handed over from the Send tab.
  Future<void> _beamFile(File f) async {
    final int size;
    try {
      size = await f.length();
    } on Object {
      setState(() => _error = 'qr_beam.err_read'.tr());
      return;
    }
    await _encode(
      name: p.basename(f.path),
      ext: p.extension(f.path).replaceFirst('.', ''),
      size: size,
      read: f.readAsBytes,
    );
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      await _encode(
        name: f.name,
        ext: f.extension ?? '',
        size: f.lengthSync() ?? await f.length(),
        read: f.readAsBytes,
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Checks the size before reading (a beam carries a few KB, so a big file
  /// is never loaded whole), then turns the bytes into the looping frames.
  Future<void> _encode({
    required String name,
    required String ext,
    required int? size,
    required Future<Uint8List> Function() read,
  }) async {
    if (size != null && size > _maxBeamBytes) {
      setState(
        () => _error = 'qr_beam.err_too_large'.tr(
          namedArgs: {'max': formatBytes(_maxBeamBytes)},
        ),
      );
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await read();
    } on Object {
      setState(() => _error = 'qr_beam.err_read'.tr());
      return;
    }
    if (!mounted) return;
    if (bytes.length > _maxBeamBytes) {
      setState(
        () => _error = 'qr_beam.err_too_large'.tr(
          namedArgs: {'max': formatBytes(_maxBeamBytes)},
        ),
      );
      return;
    }
    final lower = ext.toLowerCase();
    final enc = encodeBeam(
      Uint8List.fromList(bytes),
      chunkSize: _chunkBytes,
      name: name,
      mime: lower.isEmpty ? 'application/octet-stream' : lower,
    );
    _timer?.cancel();
    setState(() {
      _beam = enc;
      _idx = 0;
      _error = null;
    });
    _start();
  }

  void _start() {
    _timer?.cancel();
    final beam = _beam;
    if (beam == null || beam.frames.length <= 1) return;
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / _fps).round()),
      (_) => setState(() => _idx = (_idx + 1) % beam.frames.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final beam = _beam;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppScreenHeader(
                title: 'qr_beam.send_title'.tr(),
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: beam == null ? _pickPrompt(t) : _beaming(t, beam),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickPrompt(AppTokens t) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AppEmptyState(
            icon: AppIcons.qrShare,
            title: 'qr_beam.send_empty_title'.tr(),
            message: 'qr_beam.send_empty_msg'.tr(),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: AppButton(
            label: 'qr_beam.pick_file'.tr(),
            icon: AppIcons.uploadFile,
            fullWidth: true,
            loading: _picking,
            onPressed: _pick,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppType.secondary.copyWith(color: t.danger),
            ),
          ),
        ],
      ],
    );
  }

  Widget _beaming(AppTokens t, EncodedBeam beam) {
    final meta = beam.meta;
    final big = meta.size > _warnBeamBytes;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Branded QR panel — gradient frame + accent finder eyes (mirrors
          // BiShareQr, but logo-less so it stays EC-M and scans fast in a loop).
          Center(child: _BeamQr(data: beam.frames[_idx])),
          const SizedBox(height: 16),
          // Frame progress bar (looping).
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: beam.frames.length <= 1
                  ? 1
                  : (_idx + 1) / beam.frames.length,
              minHeight: 5,
              backgroundColor: t.line,
              color: t.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'qr_beam.frame_of'.tr(
              namedArgs: {'i': '${_idx + 1}', 'n': '${beam.frames.length}'},
            ),
            textAlign: TextAlign.center,
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          const SizedBox(height: 18),
          AppCard(
            margin: EdgeInsets.zero,
            child: Row(
              children: [
                AppSvgIcon(AppIcons.fileDocument, size: 20, color: t.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowStrong.copyWith(color: t.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatBytes(meta.size)} · ${'qr_beam.chunks'.tr(namedArgs: {'n': '${meta.total}'})}',
                        style: AppType.secondary.copyWith(color: t.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'qr_beam.keep_steady'.tr(),
            textAlign: TextAlign.center,
            style: AppType.secondary.copyWith(color: t.text2),
          ),
          if (big) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppSvgIcon(AppIcons.circleAlert, size: 15, color: t.accent),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'qr_beam.large_warn'.tr(),
                    style: AppType.secondary.copyWith(color: t.text2),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          // Speed control.
          Row(
            children: [
              Text(
                'qr_beam.speed'.tr(),
                style: AppType.secondary.copyWith(color: t.text2),
              ),
              Expanded(
                child: Slider(
                  value: _fps,
                  min: 3,
                  max: 12,
                  divisions: 9,
                  label: '${_fps.round()} fps',
                  activeColor: t.accent,
                  onChanged: (v) => setState(() => _fps = v),
                  onChangeEnd: (_) => _start(),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${_fps.round()} fps',
                  textAlign: TextAlign.right,
                  style: AppType.secondary.copyWith(color: t.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppButton(
            label: 'qr_beam.pick_another'.tr(),
            icon: AppIcons.uploadFile,
            variant: AppButtonVariant.secondary,
            fullWidth: true,
            loading: _picking,
            onPressed: _pick,
          ),
        ],
      ),
    );
  }
}

/// Branded QR frame for the beam stream: a gradient accent border and a white
/// panel with accent-coloured finder eyes (mirrors [BiShareQr]). Deliberately
/// logo-less and error-correction M so each frame stays small and scans quickly
/// as the stream loops.
class _BeamQr extends StatelessWidget {
  const _BeamQr({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // White under the code in both themes, so every camera reads it.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.line),
      ),
      child: QrImageView(
        data: data,
        version: QrVersions.auto,
        size: 300,
        backgroundColor: Colors.white,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: t.accent),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0A0A0A),
        ),
      ),
    );
  }
}
