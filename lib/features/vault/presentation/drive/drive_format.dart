import 'dart:io';

import 'package:easy_localization/easy_localization.dart';

import '../../../../core/storage/app_database.dart';
import '../../data/vault_downloads.dart';

/// Sizes the way the quota counts them: 1 GB = 1,000,000,000 bytes. Whole
/// numbers lose their decimals ("5 GB", not "5.00 GB"). Isolated (FSI…PDI)
/// so "100 GB" keeps its order inside Arabic text instead of showing as
/// "GB 100".
String decimalBytes(int bytes) => '\u2068${plainBytes(bytes)}\u2069';

/// [decimalBytes] without the isolate, for tests and logs.
String plainBytes(int bytes) {
  String n(double v, int digits) {
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${n(bytes / 1000, 0)} KB';
  if (bytes < 1000 * 1000 * 1000) return '${n(bytes / 1e6, 1)} MB';
  if (bytes < 1e12) return '${n(bytes / 1e9, bytes < 10e9 ? 2 : 1)} GB';
  return '${n(bytes / 1e12, 2)} TB';
}

/// A name the local file system takes.
String safeFileName(String name) => VaultDownloads.safeName(name);

/// A path in [dir] for [name] that no file uses yet ("name (1).ext", …).
File freeLocalFile(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = name;
  for (var n = 1; ; n++) {
    final f = File('${dir.path}${Platform.pathSeparator}$candidate');
    if (!f.existsSync() && !Directory(f.path).existsSync()) return f;
    candidate = '$stem ($n)$ext';
  }
}

bool isMedia(String? mime) =>
    mime != null && (mime.startsWith('image/') || mime.startsWith('video/'));

/// What kind of file this is, in words ("PDF document", "JPEG image").
String kindLabel(VaultObject o) {
  final mime = o.mime ?? '';
  final dot = o.name.lastIndexOf('.');
  final ext = dot > 0 ? o.name.substring(dot + 1).toUpperCase() : '';
  final family = switch (mime.split('/').first) {
    'image' => 'vault.kind_image',
    'video' => 'vault.kind_video',
    'audio' => 'vault.kind_audio',
    'text' => 'vault.kind_text',
    _ when mime == 'application/pdf' => 'vault.kind_pdf',
    _ when mime.contains('zip') || mime.contains('compressed') =>
      'vault.kind_archive',
    _ => 'vault.kind_file',
  };
  final word = family.tr();
  return ext.isEmpty || family == 'vault.kind_pdf' ? word : '$ext · $word';
}

/// "Oct 20" this year, "Oct 20, 2024" otherwise; time today.
String shortWhen(int ms, String locale) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return DateFormat.jm(locale).format(t);
  }
  if (t.year == now.year) return DateFormat.MMMd(locale).format(t);
  return DateFormat.yMMMd(locale).format(t);
}
