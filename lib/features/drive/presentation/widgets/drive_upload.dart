import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/ui/app_ui.dart';
import '../../data/drive_service.dart';
import '../drive_cubit.dart';

/// Uploads [files] into [folderId] behind a premium glass progress modal
/// (determinate ring + per-file count + Cancel), reusing the app's download-modal
/// visual language. Returns the number of files that uploaded successfully.
Future<int> showDriveUpload(
  BuildContext context, {
  required DriveService service,
  required List<File> files,
  String? folderId,
}) async {
  if (files.isEmpty) return 0;
  final count = await showGlassModal<int>(
    context,
    dismissible: false,
    builder: (ctx) =>
        _UploadModal(service: service, files: files, folderId: folderId),
  );
  return count ?? 0;
}

class _UploadModal extends StatefulWidget {
  const _UploadModal({
    required this.service,
    required this.files,
    required this.folderId,
  });

  final DriveService service;
  final List<File> files;
  final String? folderId;

  @override
  State<_UploadModal> createState() => _UploadModalState();
}

class _UploadModalState extends State<_UploadModal> {
  final _cancel = CancelToken();
  int _index = 0;
  int _done = 0;
  int _sent = 0;
  int _total = 0;
  String? _errorKey;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (var i = 0; i < widget.files.length; i++) {
      if (_cancel.isCancelled) break;
      final file = widget.files[i];
      if (mounted) {
        setState(() {
          _index = i;
          _sent = 0;
          _total = 0;
        });
      }
      try {
        await widget.service.upload(
          file,
          folderId: widget.folderId,
          onProgress: (sent, total) {
            if (mounted) {
              setState(() {
                _sent = sent;
                _total = total;
              });
            }
          },
          cancel: _cancel,
        );
        _done++;
      } on Object catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) break;
        // Surface the first failure, then stop the batch.
        if (mounted) setState(() => _errorKey = driveErrorKey(e));
        break;
      }
    }
    _finish();
  }

  void _finish() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(_done);
  }

  void _onCancel() {
    if (_closing) return;
    if (!_cancel.isCancelled) _cancel.cancel('user');
    _finish();
  }

  @override
  void dispose() {
    if (!_cancel.isCancelled) _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final n = widget.files.length;
    final name = widget.files[_index].uri.pathSegments.last;
    final fraction = _total > 0 ? _sent / _total : null;
    final pct = fraction != null ? (fraction * 100).clamp(0, 100).toInt() : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: fraction,
                      strokeWidth: 5,
                      backgroundColor: cs.muted,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                  if (pct != null)
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.foreground,
                      ),
                    )
                  else
                    AppSvgIcon(AppIcons.uploadFile, size: 22, color: cs.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            n > 1
                ? 'drive.uploading_n'.tr(
                    namedArgs: {'current': '${_index + 1}', 'total': '$n'},
                  )
                : 'drive.uploading'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          if (_total > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${formatBytes(_sent)} / ${formatBytes(_total)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.mutedForeground),
            ),
          ],
          if (_errorKey != null) ...[
            const SizedBox(height: 6),
            Text(
              _errorKey!.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.destructive),
            ),
          ],
          const SizedBox(height: 20),
          ShadButton.outline(
            size: ShadButtonSize.lg,
            onPressed: _onCancel,
            child: Text('common.cancel'.tr()),
          ),
        ],
      ),
    );
  }
}
