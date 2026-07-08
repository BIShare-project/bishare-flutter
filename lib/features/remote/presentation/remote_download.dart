import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/server/transfer_types.dart';
import '../../../core/ui/app_ui.dart';
import '../data/cloud_transfer_service.dart';

/// Runs a remote download behind a premium glass progress modal (determinate
/// ring + Cancel). On success shows a success toast (the file is already in the
/// Inbox); on failure an error toast; on cancel, silent. Reused by every
/// deep-link / QR download action.
Future<void> showRemoteDownload(
  BuildContext context, {
  required String label,
  required Future<ReceivedFile> Function(ProgressCb onProgress, CancelToken cancel)
  run,
}) async {
  final messenger = context; // for the post-close toast
  final result = await showGlassModal<_DownloadOutcome>(
    context,
    dismissible: false,
    builder: (ctx) => _DownloadModal(label: label, run: run),
  );
  if (result == null || !messenger.mounted) return;
  switch (result) {
    case _DownloadOk(:final file):
      toast(messenger, 'remote.saved_file'.tr(namedArgs: {'name': file.fileName}), type: ToastType.success);
    case _DownloadFailed(:final message):
      toast(messenger, message, type: ToastType.error);
    case _DownloadCancelled():
      break;
  }
}

sealed class _DownloadOutcome {
  const _DownloadOutcome();
}

class _DownloadOk extends _DownloadOutcome {
  const _DownloadOk(this.file);
  final ReceivedFile file;
}

class _DownloadFailed extends _DownloadOutcome {
  const _DownloadFailed(this.message);
  final String message;
}

class _DownloadCancelled extends _DownloadOutcome {
  const _DownloadCancelled();
}

class _DownloadModal extends StatefulWidget {
  const _DownloadModal({required this.label, required this.run});

  final String label;
  final Future<ReceivedFile> Function(ProgressCb, CancelToken) run;

  @override
  State<_DownloadModal> createState() => _DownloadModalState();
}

class _DownloadModalState extends State<_DownloadModal> {
  final _cancel = CancelToken();
  int _received = 0;
  int _total = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final file = await widget.run((r, t) {
        if (mounted) {
          setState(() {
            _received = r;
            _total = t;
          });
        }
      }, _cancel);
      _finish(_DownloadOk(file));
    } on Object catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        return; // handled by the cancel button
      }
      _finish(_DownloadFailed(describeDownloadError(e)));
    }
  }

  void _finish(_DownloadOutcome outcome) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(outcome);
  }

  void _onCancel() {
    if (_closing) return;
    _cancel.cancel('user');
    _finish(const _DownloadCancelled());
  }

  @override
  void dispose() {
    if (!_cancel.isCancelled) _cancel.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final fraction = _total > 0 ? _received / _total : null;
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
                    AppSvgIcon(AppIcons.downloadFile, size: 22, color: cs.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Downloading',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: cs.mutedForeground),
          ),
          if (_total > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${formatBytes(_received)} / ${formatBytes(_total)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.mutedForeground),
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
