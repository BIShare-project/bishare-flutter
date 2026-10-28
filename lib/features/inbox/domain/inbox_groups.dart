import '../../../core/storage/app_database.dart';

/// Received files that arrived together: one sender, one sitting.
class InboxGroup {
  InboxGroup(this.alias, this.records);

  final String alias;

  /// Newest first.
  final List<TransferRecord> records;

  DateTime get newest => records.first.timestamp;

  /// Photos and videos, shown as a grid.
  List<TransferRecord> get media => records.where(isMedia).toList();

  /// Everything else, shown as rows.
  List<TransferRecord> get files => records.where((r) => !isMedia(r)).toList();

  int get bytes => records.fold(0, (s, r) => s + r.fileSize);
}

bool isImage(TransferRecord r) => (r.fileType ?? '').startsWith('image/');

bool isMedia(TransferRecord r) {
  final t = r.fileType ?? '';
  return t.startsWith('image/') || t.startsWith('video/');
}

/// Groups received files by sender and sitting, newest group first. Files
/// from one sender belong together while each arrived within [gap] of the
/// one before it; a pause longer than that, or another sender in between,
/// starts a new group.
List<InboxGroup> groupReceived(
  List<TransferRecord> items, {
  Duration gap = const Duration(minutes: 5),
}) {
  final sorted = [...items]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final groups = <InboxGroup>[];
  String key(TransferRecord r) => r.deviceFingerprint ?? r.deviceAlias;
  for (final r in sorted) {
    final last = groups.isEmpty ? null : groups.last;
    if (last != null &&
        key(last.records.last) == key(r) &&
        last.records.last.timestamp.difference(r.timestamp) <= gap) {
      last.records.add(r);
    } else {
      groups.add(InboxGroup(r.deviceAlias, [r]));
    }
  }
  return groups;
}

final _datePrefix = RegExp(r'^\d{4}-\d{2}-\d{2}_');

/// The name the sender gave the file. A received file is saved as
/// `{yyyy-MM-dd}_{sender}_{name}` (ReceiveNaming); lists show `{name}`, and
/// the detail sheet keeps the full saved name. A name that does not carry
/// exactly this sender's prefix is shown whole.
String shownName(TransferRecord r) => shownFileName(r.fileName, r.deviceAlias);

/// [shownName] for a bare saved name and the sender's alias (the File
/// manager works from files on disk, not records).
String shownFileName(String name, String alias) {
  if (!_datePrefix.hasMatch(name)) return name;
  final rest = name.substring(11);
  alias = alias.trim();
  for (final variant in {
    alias.replaceAll(' ', '-'),
    alias.replaceAll(' ', '_'),
    alias,
  }) {
    if (variant.isNotEmpty && rest.startsWith('${variant}_')) {
      final shown = rest.substring(variant.length + 1);
      return shown.isEmpty ? name : shown;
    }
  }
  return name;
}
