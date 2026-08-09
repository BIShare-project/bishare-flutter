import 'dart:async';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/ui/app_ui.dart';
import '../domain/beam_codec.dart';

/// Max payload for QR Beam. QR throughput is tiny (~1 KB/frame), so this is for
/// text, keys, and small docs — not media. Above this we refuse with a message.
const int _maxBeamBytes = 100 * 1024;
const int _warnBeamBytes = 30 * 1024;

class QrBeamSendPage extends StatefulWidget {
  const QrBeamSendPage({super.key});

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
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null) {
        setState(() => _error = 'qr_beam.err_read'.tr());
        return;
      }
      if (bytes.length > _maxBeamBytes) {
        setState(() => _error = 'qr_beam.err_too_large'.tr(
              namedArgs: {'max': formatBytes(_maxBeamBytes)},
            ));
        return;
      }
      final ext = (f.extension ?? '').toLowerCase();
      final enc = encodeBeam(
        Uint8List.fromList(bytes),
        name: f.name,
        mime: ext.isEmpty ? 'application/octet-stream' : ext,
      );
      _timer?.cancel();
      setState(() {
        _beam = enc;
        _idx = 0;
      });
      _start();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
    final cs = ShadTheme.of(context).colorScheme;
    final beam = _beam;

    return Scaffold(
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
                child: beam == null
                    ? _pickPrompt(cs)
                    : _beaming(cs, beam),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickPrompt(ShadColorScheme cs) {
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
              style: TextStyle(color: cs.destructive, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _beaming(ShadColorScheme cs, EncodedBeam beam) {
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
              value: beam.frames.length <= 1 ? 1 : (_idx + 1) / beam.frames.length,
              minHeight: 5,
              backgroundColor: cs.muted,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'qr_beam.frame_of'.tr(namedArgs: {
              'i': '${_idx + 1}',
              'n': '${beam.frames.length}',
            }),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: cs.mutedForeground),
          ),
          const SizedBox(height: 18),
          AppCard(
            margin: EdgeInsets.zero,
            child: Row(
              children: [
                AppSvgIcon(AppIcons.fileDocument, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatBytes(meta.size)} · ${'qr_beam.chunks'.tr(namedArgs: {'n': '${meta.total}'})}',
                        style: TextStyle(fontSize: 12.5, color: cs.mutedForeground),
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
            style: TextStyle(fontSize: 12.5, height: 1.5, color: cs.mutedForeground),
          ),
          if (big) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppSvgIcon(AppIcons.circleAlert, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'qr_beam.large_warn'.tr(),
                    style: TextStyle(fontSize: 12, color: cs.mutedForeground),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          // Speed control.
          Row(
            children: [
              Text('qr_beam.speed'.tr(),
                  style: TextStyle(fontSize: 12.5, color: cs.mutedForeground)),
              Expanded(
                child: Slider(
                  value: _fps,
                  min: 3,
                  max: 12,
                  divisions: 9,
                  label: '${_fps.round()} fps',
                  activeColor: cs.primary,
                  onChanged: (v) => setState(() => _fps = v),
                  onChangeEnd: (_) => _start(),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${_fps.round()} fps',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, color: cs.mutedForeground)),
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
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, cs.primary.withValues(alpha: 0.3)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.22),
            blurRadius: 34,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: QrImageView(
          data: data,
          version: QrVersions.auto,
          size: 250,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: cs.primary,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF0A0A0A),
          ),
        ),
      ),
    );
  }
}
