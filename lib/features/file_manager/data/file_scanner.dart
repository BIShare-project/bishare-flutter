import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../../core/server/receive_folders.dart';
import '../../../core/storage/app_database.dart';
import '../domain/managed_file.dart';

/// Scans the receive directory (recursively) and joins each file against the
/// [TransferRecords] rows (by savedPath) to recover sender / MIME / encrypted.
/// The filesystem is the source of truth; drift only enriches.
class FileScanner {
  FileScanner._();

  static final _known = ReceiveFolders.categories.toSet();

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
    // Folders chosen for a type can sit outside the save folder; list them too
    // (once, if one is inside another).
    final roots = <Directory>[dir];
    for (final d in ReceiveFolders.customDirs()) {
      if (!d.existsSync()) continue;
      final inside = roots.any(
        (r) => p.isWithin(r.path, d.path) || p.equals(r.path, d.path),
      );
      if (!inside) roots.add(d);
    }
    final entities = [
      for (final (i, r) in roots.indexed)
        for (final e in r.listSync(recursive: true, followLinks: false))
          (e, i > 0),
    ];
    for (final (entity, chosenFolder) in entities) {
      if (entity is! File) continue;
      // A folder chosen for a type may hold the person's other files (a
      // camera folder, say): from there, only what BIShare received.
      if (chosenFolder && !byPath.containsKey(entity.path)) continue;
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
          // Empty when no record names the sender; the page says so.
          sender: rec?.deviceAlias ?? '',
          fileType: rec?.fileType ?? lookupMimeType(name),
          encrypted: rec?.encrypted ?? false,
          recordId: rec?.id,
        ),
      );
    }
    return out;
  }

  /// Prefer the category subfolder the receiver saved into; else the type
  /// the receiver would give it (ReceiveFolders, the same rule).
  static String _category(String path, String name, String? mime) {
    final parent = p.basename(p.dirname(path));
    if (_known.contains(parent)) return parent;
    for (final c in ReceiveFolders.categories) {
      final chosen = ReceiveFolders.custom[c];
      if (chosen != null && chosen.isNotEmpty && p.isWithin(chosen, path)) {
        return c;
      }
    }
    return ReceiveFolders.categoryOf(name, mime);
  }
}
