import 'dart:io';

import 'package:flutter/services.dart';

/// A file in the granted Documents folder: [id] is what [DocFolderChannel.copy]
/// takes (a document URI on Android, a path on iOS).
class FolderDoc {
  const FolderDoc({
    required this.id,
    required this.name,
    required this.size,
    required this.modified,
    this.mime,
  });

  final String id;
  final String name;
  final int size;
  final DateTime modified;
  final String? mime;
}

/// The folder the Send tab's Documents list reads (redesign-plan.md 3.6, 3.6b).
///
/// Android grants it through the Storage Access Framework (a persisted tree
/// URI, no all-files permission); iOS through a security-scoped bookmark of
/// a folder picked in Files. Native code: `DocFolder.kt`, `AppDelegate.swift`.
class DocFolderChannel {
  const DocFolderChannel._();

  static const _channel = MethodChannel('app.bishare/folder');

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// The granted folder's name, or null when none is granted.
  static Future<String?> restore() async {
    final m = await _call<Map<Object?, Object?>>('docsRestore');
    return m?['name'] as String?;
  }

  /// Asks for a folder; its name, or null when cancelled.
  static Future<String?> pick() async {
    final m = await _call<Map<Object?, Object?>>('docsPick');
    return m?['name'] as String?;
  }

  static Future<List<FolderDoc>> list() async {
    final raw = await _call<List<Object?>>('docsList') ?? const [];
    return [
      for (final e in raw.whereType<Map<Object?, Object?>>())
        FolderDoc(
          id: e['id']! as String,
          name: e['name']! as String,
          size: (e['size'] as num?)?.toInt() ?? 0,
          modified: DateTime.fromMillisecondsSinceEpoch(
            (e['modified'] as num?)?.toInt() ?? 0,
          ),
          mime: (e['mime'] as String?)?.isEmpty ?? true
              ? null
              : e['mime'] as String?,
        ),
    ];
  }

  /// Copies [doc] to a local path for sending; null when it failed.
  static Future<String?> copy(FolderDoc doc) =>
      _call<String>('docsCopy', {'id': doc.id});

  static Future<void> clear() => _call<void>('docsClear');

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
