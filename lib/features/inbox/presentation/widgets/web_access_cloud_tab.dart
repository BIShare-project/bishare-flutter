import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/di/locator.dart';
import '../../../../core/identity/device_identity.dart';
import '../../../../core/ui/app_ui.dart';
import '../../../remote/data/cloud_transfer_service.dart';
import '../../../remote/presentation/widgets/done_view.dart';
import '../../../remote/presentation/widgets/error_view.dart';
import '../../../remote/presentation/widgets/uploading_view.dart';

/// The "Cloud link" tab of the Browser-access sheet: pick a file → upload it
/// as a 24h one-time cloud transfer → show the ABC-DEF code + QR. Deliberately
/// a thin shell over the existing Remote-Share pieces — the SAME
/// [CloudTransferService.uploadTransfer] call and the SAME [DoneView] /
/// [UploadingView] / [ErrorView] widgets, so the two entry points can never
/// drift apart.
class WebAccessCloudTab extends StatefulWidget {
  const WebAccessCloudTab({super.key});

  @override
  State<WebAccessCloudTab> createState() => _WebAccessCloudTabState();
}

enum _Phase { pick, uploading, done, error }

class _WebAccessCloudTabState extends State<WebAccessCloudTab> {
  final CancelToken _cancel = CancelToken();
  _Phase _phase = _Phase.pick;
  double _fraction = 0;
  String _name = '';
  int _size = 0;
  CloudUploadResult? _result;
  String _error = '';

  @override
  void dispose() {
    if (!_cancel.isCancelled) _cancel.cancel();
    super.dispose();
  }

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles();
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final file = File(path);
    final name = file.uri.pathSegments.last;
    setState(() {
      _phase = _Phase.uploading;
      _fraction = 0;
      _name = name;
      _size = file.existsSync() ? file.lengthSync() : 0;
    });
    try {
      final result = await getIt<CloudTransferService>().uploadTransfer(
        file: file,
        fileName: name,
        mimeType: lookupMimeType(name) ?? 'application/octet-stream',
        senderAlias: getIt<DeviceIdentity>().alias,
        onProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _fraction = sent / total);
        },
        cancel: _cancel,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _Phase.done;
      });
    } on Object catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (!mounted) return;
      setState(() {
        _error = describeDownloadError(e);
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return switch (_phase) {
      _Phase.pick => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'inbox.web_cloud_hint'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.4,
              color: cs.mutedForeground,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ShadButton(
              size: ShadButtonSize.lg,
              leading: const AppSvgIcon(AppIcons.uploadFile, size: 18),
              onPressed: _pickAndUpload,
              child: Text('inbox.web_cloud_pick'.tr()),
            ),
          ),
        ],
      ),
      _Phase.uploading => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: UploadingView(fraction: _fraction, name: _name, size: _size),
      ),
      _Phase.done => DoneView(result: _result!),
      _Phase.error => ErrorView(
        message: _error,
        onRetry: () => setState(() => _phase = _Phase.pick),
      ),
    };
  }
}
