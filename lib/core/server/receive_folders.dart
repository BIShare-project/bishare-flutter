import 'dart:io';

import 'package:mime/mime.dart';

/// Where a received file goes: one place that every receive path asks (LAN
/// transfers, rooms, links, the browser, the clipboard), so the "Folders by
/// type" setting applies the same way to all of them.
///
/// By default a file lands in a subfolder of the save folder named after its
/// type (BIShare/Images, BIShare/Videos, …), as receivers always have. The
/// person can turn the sorting off (everything in BIShare/) or point any type
/// at a folder of their own, on the platforms that can write outside the app
/// (Android with All files access, Windows, Linux).
class ReceiveFolders {
  ReceiveFolders._();

  /// The type subfolders, in display order. The names are the folders on
  /// disk and must stay as they are: received files already live in them.
  static const categories = [
    'Images',
    'Videos',
    'Audio',
    'Documents',
    'Apps',
    'Archives',
    'Other',
  ];

  /// Sort received files into type subfolders (the default).
  static bool sortByType = true;

  /// A folder the person chose for a type, by category name. A type without
  /// one uses its subfolder of the save folder.
  static Map<String, String> custom = const {};

  /// The type of a file from its name and MIME type.
  static String categoryOf(String fileName, String? mimeType) {
    final ext = _ext(fileName);
    final mime =
        (mimeType == null || mimeType.isEmpty
                ? (lookupMimeType(fileName) ?? '')
                : mimeType)
            .toLowerCase();
    if (_apps.contains(ext) ||
        mime == 'application/vnd.android.package-archive') {
      return 'Apps';
    }
    if (mime.startsWith('image/')) return 'Images';
    if (mime.startsWith('video/')) return 'Videos';
    if (mime.startsWith('audio/')) return 'Audio';
    if (_documents.contains(ext) ||
        mime.startsWith('text/') ||
        mime.contains('pdf') ||
        mime.contains('msword') ||
        mime.contains('officedocument') ||
        mime.contains('opendocument') ||
        mime.contains('ms-excel') ||
        mime.contains('ms-powerpoint') ||
        mime.contains('epub') ||
        mime.contains('rtf')) {
      return 'Documents';
    }
    if (_archives.contains(ext) ||
        mime.contains('zip') ||
        mime.contains('tar') ||
        mime.contains('compress') ||
        mime.contains('archive') ||
        mime.contains('rar') ||
        mime.contains('7z')) {
      return 'Archives';
    }
    return 'Other';
  }

  /// The folder [fileName] is saved into under [saveDir], created if missing.
  static Directory dirFor(
    Directory saveDir,
    String fileName,
    String? mimeType,
  ) {
    if (!sortByType) return _ensure(saveDir);
    final category = categoryOf(fileName, mimeType);
    final chosen = custom[category];
    if (chosen != null && chosen.isNotEmpty) {
      final dir = Directory(chosen);
      try {
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return dir;
      } on FileSystemException {
        // The chosen folder went away or became read-only: fall back to the
        // default rather than failing the transfer.
      }
    }
    return _ensure(
      Directory('${saveDir.path}${Platform.pathSeparator}$category'),
    );
  }

  /// Folders of their own the person chose, which the file browser also
  /// lists (they can sit outside the save folder).
  static List<Directory> customDirs() => [
    for (final c in categories)
      if ((custom[c] ?? '').isNotEmpty) Directory(custom[c]!),
  ];

  static Directory _ensure(Directory d) {
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static const _apps = {
    'apk',
    'apks',
    'xapk',
    'apkm',
    'aab',
    'ipa',
    'exe',
    'msi',
    'msix',
    'appx',
    'dmg',
    'pkg',
    'appimage',
    'deb',
    'rpm',
    'snap',
    'flatpak',
  };

  static const _documents = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'rtf',
    'txt',
    'md',
    'csv',
    'epub',
    'pages',
    'numbers',
    'key',
  };

  static const _archives = {
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'tgz',
    'bz2',
    'xz',
    'zst',
  };
}
