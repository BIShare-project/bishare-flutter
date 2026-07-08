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

  Future<void> init() async {
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
      await requestPermission();
    } on Object {
      _ready = false;
    }
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

  /// Notify on every received file. Idempotent.
  void attach(TransferServer server) {
    _sub ??= server.received.listen(_notify);
  }

  Future<void> _notify(ReceivedFile f) => notify(
    'notification.file_received'.tr(),
    'notification.from'.tr(
      namedArgs: {'file': f.fileName, 'sender': f.senderAlias},
    ),
  );

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
    await _sub?.cancel();
    _sub = null;
  }
}
