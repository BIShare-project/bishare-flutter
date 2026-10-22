import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'vault_account.dart';

/// One reminder: when, and what it says.
typedef VaultReminder = ({int id, DateTime at, String title, String body});

/// Reminders on the dates the app knows (drive-plan.md "Vault states", task
/// 7.6). The server has no email address to warn anyone, so the app says it
/// itself: a plan that will not renew ending, a read-only Drive about to be
/// emptied, a free Drive nobody has opened for almost a year. Scheduled
/// again whenever what the server said changes, and once a day at most for
/// the free Drive (each opening pushes its date out by a year).
class VaultReminders {
  VaultReminders({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  String? _scheduled;
  bool _channel = false;

  static const _ids = [7101, 7102, 7103, 7104, 7105];

  /// Before a read-only Drive is emptied.
  static const _lapseWarn = [Duration(days: 7), Duration(days: 1)];

  /// Before a plan that will not renew ends.
  static const _endWarn = Duration(days: 3);

  /// Before the free plan's 12 months without use run out.
  static const _freeWarn = [Duration(days: 30), Duration(days: 7)];

  static bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS);

  /// What to remind of for a Drive as the server last described it, at
  /// [now]. [date] writes a date the way the person reads them.
  static List<VaultReminder> plan({
    required bool ready,
    required String state,
    required String? plan,
    required DateTime? planEnds,
    required bool? renews,
    required DateTime? lapseEnds,
    required DateTime now,
    required String Function(DateTime) date,
  }) {
    if (!ready) return const [];
    final out = <VaultReminder>[];
    final lapse = lapseEnds;
    final ends = planEnds;
    final paid = (plan ?? 'free') != 'free';
    if (state == 'lapsed' && lapse != null) {
      for (final (i, before) in _lapseWarn.indexed) {
        out.add((
          id: _ids[i],
          at: lapse.subtract(before),
          title: 'vault.remind_lapse_title'.tr(),
          body: 'vault.remind_lapse_body'.tr(namedArgs: {'date': date(lapse)}),
        ));
      }
    } else if (paid && renews == false && ends != null) {
      out.add((
        id: _ids[2],
        at: ends.subtract(_endWarn),
        title: 'vault.remind_end_title'.tr(),
        body: 'vault.remind_end_body'.tr(namedArgs: {'date': date(ends)}),
      ));
    } else if (!paid && state == 'free') {
      final deleted = now.add(const Duration(days: 365));
      for (final (i, before) in _freeWarn.indexed) {
        out.add((
          id: _ids[3 + i],
          at: deleted.subtract(before),
          title: 'vault.remind_free_title'.tr(),
          body: 'vault.remind_free_body'.tr(namedArgs: {'date': date(deleted)}),
        ));
      }
    }
    return [
      for (final r in out)
        if (r.at.isAfter(now)) r,
    ];
  }

  /// Cancel what was scheduled and schedule [plan] again, when it changed.
  Future<void> sync(VaultAccount a, String Function(DateTime) date) async {
    if (!supported) return;
    final now = DateTime.now();
    final key = [
      a.status.name,
      a.state,
      a.plan,
      a.planEnds?.millisecondsSinceEpoch,
      a.planRenews,
      a.lapseEnds?.millisecondsSinceEpoch,
      if (a.state == 'free') now.toIso8601String().substring(0, 10),
    ].join('|');
    if (key == _scheduled) return;
    _scheduled = key;
    try {
      for (final id in _ids) {
        await _plugin.cancel(id: id);
      }
      if (!_channel) {
        _channel = true;
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'bishare_drive',
                'Drive',
                description: 'Reminders about your Drive plan',
              ),
            );
      }
      final due = plan(
        ready: a.status == VaultStatus.ready && a.infoLoaded,
        state: a.state,
        plan: a.plan,
        planEnds: a.planEnds,
        renews: a.planRenews,
        lapseEnds: a.lapseEnds,
        now: now,
        date: date,
      );
      for (final r in due) {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'bishare_drive',
              'Drive',
              channelDescription: 'Reminders about your Drive plan',
            ),
            iOS: DarwinNotificationDetails(presentAlert: true),
            macOS: DarwinNotificationDetails(presentAlert: true),
          ),
        );
      }
    } on Object catch (e) {
      // Best effort, like every local notification here.
      debugPrint('[vault] reminders: $e');
    }
  }
}
