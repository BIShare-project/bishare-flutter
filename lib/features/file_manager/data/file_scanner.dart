import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../core/storage/app_database.dart';
import '../domain/managed_file.dart';

/// Scans the receive directory (recursively) and joins each file against the
/// [TransferRecords] rows (by savedPath) to recover sender / MIME / encrypted.
/// The filesystem is the source of truth; drift only enriches.
class FileScanner {
  FileScanner._();

  static const _known = {
    'Images',
    'Videos',
    'Audio',
    'Documents',
    'Archives',
    'Other',
  };

  static Future<List<ManagedFile>> scan(
    Directory dir,
    List<TransferRecord> received,
  ) async {
    if (!dir.existsSync()) return const [];
    final byPath = {
      for (final r in received)
        if (r.savedPath != null) r.savedPath!: r,
    };
    final out = <ManagedFile>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue; // skip .<uuid>.part temp files
      final FileStat st;
      try {
        st = entity.statSync();
      } on FileSystemException {
        continue;
      }
      final rec = byPath[entity.path];
      out.add(
        ManagedFile(
          name: name,
          path: entity.path,
          size: st.size,
          modified: st.modified,
          category: _category(entity.path, name, rec?.fileType),
          sender: (rec?.deviceAlias.isNotEmpty ?? false)
              ? rec!.deviceAlias
              : 'Unknown',
          fileType: rec?.fileType ?? lookupMimeType(name),
          encrypted: rec?.encrypted ?? false,
          recordId: rec?.id,
        ),
      );
    }
    return out;
  }

  /// Prefer the category subfolder the receiver saved into; else derive from the
  /// MIME/extension.
  static String _category(String path, String name, String? mime) {
    final parent = p.basename(p.dirname(path));
    if (_known.contains(parent)) return parent;
    final m = mime ?? lookupMimeType(name) ?? '';
    if (m.startsWith('image/')) return 'Images';
    if (m.startsWith('video/')) return 'Videos';
    if (m.startsWith('audio/')) return 'Audio';
    if (m.startsWith('text/') ||
        m.contains('pdf') ||
        m.contains('word') ||
        m.contains('document')) {
      return 'Documents';
    }
    if (m.contains('zip') ||
        m.contains('archive') ||
        m.contains('compressed')) {
      return 'Archives';
    }
    return 'Other';
  }
}
