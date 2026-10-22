import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/app_database.dart';
import '../../../core/storage/vault_tables.dart';
import '../presentation/drive/drive_format.dart';
import 'vault_upload_batch.dart';
import 'vault_uploader.dart';

/// Drive uploads in the notification shade while the app is not on screen
/// (owner 2026-10-21: "kenapa tidak ada notifikasi progress kalo berjalan
/// di latar?"): a quiet notification with the bar of [UploadBatch], what
/// has gone of what, and how many files are left; then "Uploads finished"
/// for a minute. Android only: iOS has no progress notifications.
///
/// It is posted again every few seconds with a short timeout, so a process
/// the system freezes cannot leave a stuck "uploading" behind.
///
/// In the app ([foreground]) the notification belongs to a foreground
/// service of type dataSync while files go up: without one, Samsung froze
/// the app seconds after it left the screen and killed it soon after
/// (logcat, owner's SM-A245F, 2026-10-22), so a backup stopped as soon as
/// the app was closed. The service starts while the app is on screen (a
/// background start is refused since Android 12) and ends with the queue.
class VaultUploadNotice {
  VaultUploadNotice({
    required VaultDao dao,
    required VaultUploader uploader,
    required SharedPreferences prefs,
    this.initialize = false,
    this.foreground = false,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _dao = dao,
       _uploader = uploader,
       _prefs = prefs,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final VaultDao _dao;
  final VaultUploader _uploader;
  final SharedPreferences _prefs;
  final FlutterLocalNotificationsPlugin _plugin;

  /// A background isolate sets the plugin up itself; the app's own isolate
  /// already did (NotificationService).
  final bool initialize;

  /// The app's isolate: hold a foreground service while files go up.
  final bool foreground;

  /// The app is out of sight: progress shows here, and "Uploads finished"
  /// after it. On screen, the notification shows only as the service's.
  bool hidden = true;
  bool _service = false;

  static const _channel = 'bishare_drive_uploads';
  static const _progressId = 7701;
  static const _doneId = 7702;
  static const _textsKey = 'vault.uploadNoticeTexts';

  static bool get supported =>
      supportedForTest ?? (!kIsWeb && Platform.isAndroid);

  @visibleForTesting
  static bool? supportedForTest;

  /// The app's isolate, with translations loaded: the words for a
  /// background run, which has none.
  static Future<void> saveTexts(SharedPreferences prefs) async {
    final texts = {
      'channel': 'vault.notify_channel'.tr(),
      'uploading': 'vault.notify_uploading'.tr(),
      'progress': 'vault.uploads_bytes'.tr(
        namedArgs: {'done': '{done}', 'total': '{total}'},
      ),
      'left': 'vault.notify_left'.tr(namedArgs: {'count': '{count}'}),
      'done': 'vault.notify_done'.tr(),
      'doneBody': 'vault.notify_done_body'.tr(namedArgs: {'count': '{count}'}),
    };
    // Not loaded yet: the keys come back as they are.
    if (texts['uploading'] == 'vault.notify_uploading') return;
    await prefs.setString(_textsKey, jsonEncode(texts));
  }

  static const _english = {
    'channel': 'Drive uploads',
    'uploading': 'Uploading to Drive',
    'progress': '{done} of {total}',
    'left': '{count} left',
    'done': 'Uploads finished',
    'doneBody': 'Uploaded: {count}',
  };

  Map<String, String> get _texts {
    try {
      final raw = _prefs.getString(_textsKey);
      if (raw != null) {
        return {
          ..._english,
          ...Map<String, String>.from(jsonDecode(raw) as Map),
        };
      }
    } on Object {
      // English, then.
    }
    return _english;
  }

  StreamSubscription<List<VaultTransfer>>? _sub;
  List<VaultTransfer> _transfers = const [];
  Timer? _tick;
  final OneWayProgress _bar = OneWayProgress();
  bool _shown = false;

  /// When the go being shown began (see [UploadBatch.start]).
  int? _since;
  String _last = '';
  DateTime _postedAt = DateTime(0);

  /// Follow the uploads until [stop].
  Future<void> start() async {
    if (!supported || _tick != null) return;
    try {
      if (initialize) {
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
      }
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            AndroidNotificationChannel(
              _channel,
              _texts['channel']!,
              importance: Importance.low,
              showBadge: false,
            ),
          );
    } on Object catch (e) {
      debugPrint('[vault] upload notice: $e');
      return;
    }
    _sub = _dao.watchTransfers().listen((t) => _transfers = t);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  /// The app is on screen again (no summary: the screen shows it), or the
  /// background run ended ([summary]: "Uploads finished" when files went).
  Future<void> stop({bool summary = false}) async {
    _tick?.cancel();
    _tick = null;
    await _sub?.cancel();
    _sub = null;
    _last = '';
    await _stopService();
    if (summary) {
      await _finish();
    } else {
      await _clear();
      _since = null;
    }
  }

  Future<void> _update() async {
    final batch = UploadBatch.of(_transfers, _uploader);
    if (batch == null || batch.running.isEmpty) {
      await _stopService();
      if (_shown && hidden) {
        await _finish();
      } else if (_shown) {
        await _clear();
        _since = null;
      }
      return;
    }
    if (!hidden && !foreground) return;
    _since = batch.start;
    final t = _texts;
    final bar = ((_bar.of(batch) ?? 0) * 1000).round();
    final body = t['progress']!
        .replaceAll('{done}', decimalBytes(batch.bytesDone))
        .replaceAll('{total}', decimalBytes(batch.bytes));
    final left = t['left']!.replaceAll('{count}', '${batch.running.length}');
    final now = DateTime.now();
    final key = '$bar|$body|$left';
    // Unchanged: posted again only to renew the timeout.
    if (key == _last && now.difference(_postedAt).inSeconds < 10) return;
    _last = key;
    _postedAt = now;
    _shown = true;
    final details = AndroidNotificationDetails(
      _channel,
      t['channel']!,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      silent: true,
      showProgress: true,
      maxProgress: 1000,
      progress: bar,
      subText: left,
      // A service's notification goes with the service; a plain one must
      // not outlive a process the system froze.
      timeoutAfter: _service || foreground ? null : 30000,
    );
    if (foreground && !_service) {
      try {
        await _android?.startForegroundService(
          id: _progressId,
          title: t['uploading'],
          body: body,
          notificationDetails: details,
          startType: AndroidServiceStartType.startNotSticky,
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          },
        );
        _service = true;
        return;
      } on Object catch (e) {
        // Refused (started while out of sight): a plain notification.
        debugPrint('[vault] upload service: $e');
      }
    }
    try {
      await _plugin.show(
        id: _progressId,
        title: t['uploading'],
        body: body,
        notificationDetails: NotificationDetails(android: details),
      );
    } on Object catch (e) {
      debugPrint('[vault] upload notice: $e');
    }
  }

  Future<void> _finish() async {
    await _clear();
    final since = _since;
    _since = null;
    if (since == null) return;
    // What finished in the go just shown.
    final count = _transfers
        .where(
          (t) =>
              t.direction == 'up' && t.state == 'done' && t.updatedAt >= since,
        )
        .length;
    if (count <= 0) return;
    final t = _texts;
    try {
      await _plugin.show(
        id: _doneId,
        title: t['done'],
        body: t['doneBody']!.replaceAll('{count}', '$count'),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            t['channel']!,
            importance: Importance.low,
            priority: Priority.low,
            silent: true,
            timeoutAfter: 60000,
          ),
        ),
      );
    } on Object catch (e) {
      debugPrint('[vault] upload notice: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _stopService() async {
    if (!_service) return;
    _service = false;
    try {
      await _android?.stopForegroundService();
    } on Object catch (e) {
      debugPrint('[vault] upload service: $e');
    }
  }

  Future<void> _clear() async {
    if (!_shown) return;
    _shown = false;
    try {
      await _plugin.cancel(id: _progressId);
    } on Object {
      // Gone already.
    }
  }
}
