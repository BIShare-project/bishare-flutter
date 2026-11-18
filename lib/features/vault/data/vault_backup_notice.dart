import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One notification when photo backup stops because the Drive is full: the
/// photos taken from then on are not in the Drive, and nothing else would
/// say so until the person opens Drive. Not shown while the app is on
/// screen (the Drive says it there), and at most once in [_again].
class VaultBackupNotice {
  VaultBackupNotice({
    required SharedPreferences prefs,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _prefs = prefs,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final SharedPreferences _prefs;
  final FlutterLocalNotificationsPlugin _plugin;

  static const _id = 7110;
  static const _channel = 'bishare_drive';
  static const _again = Duration(days: 7);
  static const _lastKey = 'vault.backupFullNoticeAt';
  static const _textsKey = 'vault.backupFullNoticeTexts';

  static bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// A background run has no translations loaded: the app saves the words in
  /// the person's language whenever it is open (VaultBackground.saveTexts).
  static Future<void> saveTexts(SharedPreferences prefs) async {
    final texts = {
      'title': 'vault.backup_full_notice_title'.tr(),
      'body': 'vault.backup_full_notice_body'.tr(),
    };
    // Not loaded yet: the keys come back as they are.
    if (texts['title'] == 'vault.backup_full_notice_title') return;
    await prefs.setString(_textsKey, jsonEncode(texts));
  }

  static const _english = {
    'title': 'Photo backup has stopped',
    'body': 'Your Drive is full. New photos and videos are not backed up.',
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

  /// When a notification may be shown again, from when the last one was.
  @visibleForTesting
  static bool due({required int? lastAtMs, required DateTime now}) =>
      lastAtMs == null ||
      now.millisecondsSinceEpoch - lastAtMs >= _again.inMilliseconds ||
      now.millisecondsSinceEpoch < lastAtMs;

  /// The app is in front of the person. A background run has no screen (and
  /// may have no binding to ask): that counts as away.
  static bool get _onScreen {
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } on Object {
      return false;
    }
  }

  /// The Drive refused a photo for lack of room.
  Future<void> full() async {
    if (!supported) return;
    // On screen: the Drive itself says it, with the way to more room.
    if (_onScreen) return;
    final now = DateTime.now();
    if (!due(lastAtMs: _prefs.getInt(_lastKey), now: now)) return;
    final texts = _texts;
    try {
      await _plugin.show(
        id: _id,
        title: texts['title'],
        body: texts['body'],
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(_channel, 'Drive'),
          iOS: DarwinNotificationDetails(presentAlert: true),
        ),
      );
      await _prefs.setInt(_lastKey, now.millisecondsSinceEpoch);
    } on Object catch (e) {
      // Best effort, like every local notification here.
      debugPrint('[vault] backup notice: $e');
    }
  }
}
