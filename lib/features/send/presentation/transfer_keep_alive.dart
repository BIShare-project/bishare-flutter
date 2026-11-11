import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../receive/presentation/receive_cubit.dart';
import '../../vault/presentation/drive/drive_format.dart';
import 'send_cubit.dart';

/// Keeps a LAN send or receive going while the screen is off or BIShare is in
/// the background.
///
/// Android: a foreground service with a progress notification, a wake lock
/// and a Wi-Fi lock (TransferKeepAliveService.kt), held from the first byte
/// to the end of the last transfer.
///
/// iOS has no such service: while a transfer runs the screen does not lock by
/// itself, and a manual lock gets the extra time iOS gives (about 30 s,
/// AppDelegate.swift). After that the transfer pauses and continues from
/// where it stopped (TCP resume) when BIShare is opened again.
class TransferKeepAlive extends StatefulWidget {
  const TransferKeepAlive({super.key, required this.child});

  final Widget child;

  @override
  State<TransferKeepAlive> createState() => _TransferKeepAliveState();
}

class _TransferKeepAliveState extends State<TransferKeepAlive> {
  static const _channel = MethodChannel('app.bishare/transfer_keepalive');
  static const _ios = MethodChannel('app.bishare/background');

  static bool get _android => !kIsWeb && Platform.isAndroid;
  static bool get _iOS => !kIsWeb && Platform.isIOS;
  static bool get _supported => _android || _iOS;

  bool _running = false;
  String _last = '';
  DateTime _postedAt = DateTime(0);

  @override
  void dispose() {
    if (_running) unawaited(_stop());
    super.dispose();
  }

  void _update() {
    if (!_supported || !mounted) return;
    final send = context.read<SendCubit>().state;
    final receive = context.read<ReceiveCubit>().state.progress;
    final sending = send.status == SendStatus.sending;
    final receiving = receive != null && !receive.isComplete;
    if (!sending && !receiving) {
      if (_running) unawaited(_stop());
      return;
    }
    final String title;
    final int done;
    final int total;
    if (sending) {
      title = 'transfer_notice.sending'.tr(
        namedArgs: {'device': send.deviceAlias},
      );
      done = send.sent;
      total = send.total;
    } else {
      final r = receive!;
      title = 'transfer_notice.receiving'.tr(
        namedArgs: {'device': r.senderAlias},
      );
      done = r.bytesReceived;
      total = r.totalBytes;
    }
    final body = total > 0
        ? 'vault.uploads_bytes'.tr(
            namedArgs: {
              'done': decimalBytes(done),
              'total': decimalBytes(total),
            },
          )
        : '';
    final progress = total > 0 ? (done * 1000 ~/ total).clamp(0, 1000) : -1;
    final key = '$title|$progress';
    final now = DateTime.now();
    // At most one notification update a second: progress arrives ~12/s.
    if (_running &&
        (key == _last || now.difference(_postedAt).inMilliseconds < 1000)) {
      return;
    }
    _last = key;
    _postedAt = now;
    final first = !_running;
    _running = true;
    unawaited(_show(title, body, progress, first: first));
  }

  Future<void> _show(
    String title,
    String body,
    int progress, {
    required bool first,
  }) async {
    if (_iOS) {
      if (!first) return;
      try {
        await _ios.invokeMethod<void>('transferStart');
      } on Object catch (e) {
        debugPrint('[KeepAlive] start: $e');
      }
      return;
    }
    try {
      await _channel.invokeMethod<bool>('show', {
        'channel': 'transfer_notice.channel'.tr(),
        'title': title,
        'body': body,
        'progress': progress,
      });
    } on Object catch (e) {
      debugPrint('[KeepAlive] show: $e');
    }
  }

  Future<void> _stop() async {
    _running = false;
    _last = '';
    try {
      if (_iOS) {
        await _ios.invokeMethod<void>('transferEnd');
      } else {
        await _channel.invokeMethod<void>('stop');
      }
    } on Object catch (e) {
      debugPrint('[KeepAlive] stop: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return widget.child;
    return MultiBlocListener(
      listeners: [
        BlocListener<SendCubit, SendState>(listener: (_, _) => _update()),
        BlocListener<ReceiveCubit, ReceiveState>(listener: (_, _) => _update()),
      ],
      child: widget.child,
    );
  }
}
