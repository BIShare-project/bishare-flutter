import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

/// A document found on the phone's shared storage.
class DeviceDoc {
  const DeviceDoc({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
}

/// One permission for everything the Send tab reads on Android (owner
/// decision 2026-10-28): "All files access" (MANAGE_EXTERNAL_STORAGE) from
/// Android 11, READ_EXTERNAL_STORAGE below. With it the photo, video and
/// audio tabs read the library and the Documents tab lists every document,
/// as file sharing apps do. Drive backup keeps its own approved READ_MEDIA
/// flow and does not depend on this.
class AllFilesAccess {
  const AllFilesAccess._();

  static bool get applies => !kIsWeb && Platform.isAndroid;

  static int? _sdk;

  static Future<bool> _allFiles() async {
    _sdk ??= (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    return _sdk! >= 30;
  }

  static Future<Permission> _permission() async =>
      await _allFiles() ? Permission.manageExternalStorage : Permission.storage;

  static Future<bool> granted() async =>
      applies && await (await _permission()).isGranted;

  /// From Android 11 this opens the app's "All files access" page in system
  /// settings; the answer counts once the person comes back.
  static Future<bool> request() async {
    if (!applies) return false;
    final permission = await _permission();
    if (await permission.isGranted) return true;
    return (await permission.request()).isGranted;
  }

  /// Every document on shared storage whose name [keep] accepts, newest
  /// first. Walks off the UI thread; other apps' private folders and hidden
  /// entries are skipped, and the walk stops at [limit] files.
  static Future<List<DeviceDoc>> documents(
    bool Function(String name) keep, {
    int limit = 3000,
  }) async {
    if (!await granted()) return const [];
    final found = await compute(_walk, (
      root: '/storage/emulated/0',
      limit: limit,
    ));
    return [
      for (final d in found)
        if (keep(d.name)) d,
    ]..sort((a, b) => b.modified.compareTo(a.modified));
  }
}

List<DeviceDoc> _walk(({String root, int limit}) args) {
  final out = <DeviceDoc>[];
  final queue = [Directory(args.root)];
  while (queue.isNotEmpty && out.length < args.limit) {
    final dir = queue.removeLast();
    final List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final e in children) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        if (e.path == '${args.root}/Android') continue;
        queue.add(e);
      } else if (e is File && _looksLikeDoc(name)) {
        try {
          final st = e.statSync();
          out.add(
            DeviceDoc(
              path: e.path,
              name: name,
              size: st.size,
              modified: st.modified,
            ),
          );
        } on FileSystemException {
          // gone or unreadable
        }
        if (out.length >= args.limit) break;
      }
    }
  }
  return out;
}

/// A cheap first cut in the isolate; the tab's own kinds decide the rest.
final _docExt = RegExp(
  r'\.(pdf|docx?|odt|rtf|pages|txt|md|xlsx?|ods|csv|numbers|pptx?|odp|key|zip|rar|7z|tar|gz|tgz|apks?)$',
  caseSensitive: false,
);

bool _looksLikeDoc(String name) => _docExt.hasMatch(name);
