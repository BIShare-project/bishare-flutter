import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../server/transfer_server.dart';
import '../server/transfer_types.dart';

/// Local notifications for received files (with sound). Best-effort: if the
/// platform lacks support or permission is denied, it silently no-ops.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  StreamSubscription<ReceivedFile>? _sub;
  int _id = 0;
  bool _ready = false;

  /// [requestNow] is false on a first run: the onboarding permission page asks
  /// for notifications in context, instead of a system prompt over the splash.
  Future<void> init({bool requestNow = true}) async {
    try {
      _ready =
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings('@mipmap/ic_launcher'),
              // We request the Darwin permission ourselves (requestPermission)
              // so the prompt is deliberate, not a side effect of init.
              iOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
              macOS: DarwinInitializationSettings(
                requestAlertPermission: false,
                requestBadgePermission: false,
                requestSoundPermission: false,
              ),
            ),
          ) ??
          true;
      // Android 8+ needs the channel to exist or show() silently drops.
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'bishare_received',
              'Received files',
              description: 'Notifies when a file arrives',
              importance: Importance.high,
            ),
          );
      // Android 13+ requires a RUNTIME grant of POST_NOTIFICATIONS (declaring it
      // in the manifest is not enough); iOS/macOS need the Darwin grant. Without
      // this, notifications silently never appear. Safe on every launch — the OS
      // only prompts once.
      if (requestNow) await requestPermission();
    } on Object {
      _ready = false;
    }
  }

  /// Whether the OS currently allows our notifications, without prompting.
  Future<bool> isPermitted() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return (await ios.checkPermissions())?.isEnabled ?? false;
      }
      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      if (mac != null) {
        return (await mac.checkPermissions())?.isEnabled ?? false;
      }
    } on Object {
      // best-effort
    }
    return false;
  }

  /// Request the OS notification permission. Idempotent (the OS prompts once).
  /// Reused by the onboarding permission page. Returns whether notifications are
  /// now permitted.
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      final mac = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      if (mac != null) {
        return await mac.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } on Object {
      // best-effort
    }
    return false;
  }

  /// One notification per finished transfer: the file's name for one file,
  /// "100 files received" for a batch. Idempotent.
  void attach(TransferServer server) {
    _server = server;
    _sub ??= server.received.listen(_collect);
  }

  TransferServer? _server;
  final _arrived = <ReceivedFile>[];
  Timer? _settle;

  void _collect(ReceivedFile f) {
    _arrived.add(f);
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 1200), _flush);
  }

  void _flush() {
    if (_arrived.isEmpty) return;
    // Still receiving: wait for the end of the transfer.
    if (_server?.isReceiving ?? false) {
      _settle = Timer(const Duration(milliseconds: 1200), _flush);
      return;
    }
    final files = [..._arrived];
    _arrived.clear();
    final sender = files.last.senderAlias;
    if (files.length == 1) {
      unawaited(
        notify(
          'notification.file_received'.tr(),
          'notification.from'.tr(
            namedArgs: {'file': files.single.fileName, 'sender': sender},
          ),
        ),
      );
    } else {
      unawaited(
        notify(
          'inbox.n_files_received'.plural(files.length),
          'inbox.from'.tr(namedArgs: {'alias': sender}),
        ),
      );
    }
  }

  /// Show a generic best-effort local notification (reused for received files,
  /// clipboard sync, etc.).
  Future<void> notify(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'bishare_received',
            'Received files',
            channelDescription: 'Notifies when a file arrives',
            importance: Importance.high,
            priority: Priority.high,
          ),
          // presentAlert is required for the banner to show while the app is in
          // the FOREGROUND (the common case — a file arrives while you're using
          // the app). Without it iOS/macOS play the sound but show nothing.
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } on Object {
      // ignore — notifications are best-effort
    }
  }

  Future<void> dispose() async {
    _settle?.cancel();
    await _sub?.cancel();
    _sub = null;
  }
}
