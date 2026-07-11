import 'package:easy_localization/easy_localization.dart';

/// A localized relative sighting time: "just now", "5 minutes ago",
/// "2 hours ago", "3 days ago", then a plain date for anything older.
/// [now] is injectable for tests.
String relativeLastSeen(DateTime lastSeen, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(lastSeen);
  if (diff.inMinutes < 1) return 'devices.just_now'.tr();
  if (diff.inHours < 1) return 'devices.minutes_ago'.plural(diff.inMinutes);
  if (diff.inDays < 1) return 'devices.hours_ago'.plural(diff.inHours);
  if (diff.inDays < 7) return 'devices.days_ago'.plural(diff.inDays);
  String p(int v) => v.toString().padLeft(2, '0');
  return '${lastSeen.year}-${p(lastSeen.month)}-${p(lastSeen.day)}';
}
