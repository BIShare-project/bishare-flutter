import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/di/locator.dart';
import '../../../core/identity/device_identity.dart';
import '../../../core/ui/app_ui.dart';
import '../data/cloud_transfer_service.dart';
import '../data/stream_relay_service.dart';
import 'widgets/done_view.dart';
import 'widgets/error_view.dart';
import 'widgets/pick_view.dart';
import 'widgets/remote_share_header.dart';
import 'widgets/stream_waiting_view.dart';
import 'widgets/uploading_view.dart';

/// Remote share — a faithful port of the native `RemoteShareView`. Opens with no
/// preconditions: pick a photo/video or file right here, choose one-time, and
/// get a private link + QR that works anywhere (no same-network requirement).
class RemoteSharePage extends StatefulWidget {
  const RemoteSharePage({super.key});

  @override
  State<RemoteSharePage> createState() => _RemoteSharePageState();
}

enum _Phase { pick, uploading, done, streamWaiting, streamSending, error }

class _RemoteSharePageState extends State<RemoteSharePage> {
  final CancelToken _cancel = CancelToken();
  _Phase _phase = _Phase.pick;
  bool _oneTime = true;
  bool _shareViaWeb = true;
  double _fraction = 0;
  String _pickedName = '';
  int _pickedSize = 0;
  CloudUploadResult? _result;
  String _streamCode = '';
  String _error = '';
  StreamSubscription<StreamSendEvent>? _streamSub;

  @override
  void dispose() {
    if (!_cancel.isCancelled) _cancel.cancel();
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _pick({required bool mediaOnly}) async {
    final res = await FilePicker.platform.pickFiles(
      type: mediaOnly ? FileType.media : FileType.any,
    );
    final path = res?.files.single.path;
    if (path == null) return;
    final file = File(path);
    if (_shareViaWeb) {
      _upload(file);
    } else {
      _streamSend(file);
    }
  }

  void _streamSend(File file) {
    final name = file.uri.pathSegments.last;
    setState(() {
      _phase = _Phase.streamWaiting;
      _pickedName = name;
      _pickedSize = file.existsSync() ? file.lengthSync() : 0;
      _fraction = 0;
      _streamCode = '';
    });
    _streamSub = getIt<StreamRelayService>()
        .send(
          file,
          fileName: name,
          mimeType: lookupMimeType(name) ?? 'application/octet-stream',
          senderAlias: getIt<DeviceIdentity>().alias,
        )
        .listen((event) {
          if (!mounted) return;
          switch (event) {
            case StreamCodeReady(:final code):
              setState(() {
                _streamCode = code;
                _phase = _Phase.streamWaiting;
              });
            case StreamReceiverJoined():
              setState(() => _phase = _Phase.streamSending);
            case StreamSendProgress(:final fraction):
              setState(() => _fraction = fraction);
            case StreamSendComplete():
              toast(context, 'remote.sent_file'.tr(namedArgs: {'name': _pickedName}), type: ToastType.success);
              Navigator.of(context).maybePop();
            case StreamSendFailed(:final message):
              setState(() {
                _error = message;
                _phase = _Phase.error;
              });
          }
        });
  }

  Future<void> _upload(File file) async {
    final name = file.uri.pathSegments.last;
    setState(() {
      _phase = _Phase.uploading;
      _fraction = 0;
      _pickedName = name;
      _pickedSize = file.existsSync() ? file.lengthSync() : 0;
    });
    try {
      final result = await getIt<CloudTransferService>().uploadTransfer(
        file: file,
        fileName: name,
        mimeType: lookupMimeType(name) ?? 'application/octet-stream',
        senderAlias: getIt<DeviceIdentity>().alias,
        oneTime: _oneTime,
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
    return Scaffold(
      backgroundColor: cs.background,
      body: SafeArea(
        child: AppResponsivePane(
          maxWidth: 520,
          child: Column(
            children: [
              RemoteShareHeader(
                showBack: _phase == _Phase.done || _phase == _Phase.error,
              ),
              Expanded(
                child: switch (_phase) {
                  _Phase.pick => PickView(
                    oneTime: _oneTime,
                    onOneTime: (v) => setState(() => _oneTime = v),
                    shareViaWeb: _shareViaWeb,
                    onShareViaWeb: (v) => setState(() => _shareViaWeb = v),
                    onMedia: () => _pick(mediaOnly: true),
                    onFile: () => _pick(mediaOnly: false),
                  ),
                  _Phase.uploading => UploadingView(
                    fraction: _fraction,
                    name: _pickedName,
                    size: _pickedSize,
                  ),
                  _Phase.done => DoneView(result: _result!),
                  _Phase.streamWaiting => StreamWaitingView(code: _streamCode),
                  _Phase.streamSending => UploadingView(
                    fraction: _fraction,
                    name: _pickedName,
                    size: _pickedSize,
                    title: 'remote.sending_directly'.tr(),
                  ),
                  _Phase.error => ErrorView(
                    message: _error,
                    onRetry: () => setState(() => _phase = _Phase.pick),
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
