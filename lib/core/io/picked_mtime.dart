import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../storage/android_downloads_channel.dart';
import 'preserve_mtime.dart';

/// The paths of a file-picker result, with the original "Date modified"
/// restored on Android.
///
/// On Android the picker hands the app a COPY in its cache, and that copy is
/// stamped with the moment it was copied — so by the time a transfer reads
/// the file's mtime the real one is already gone, and the receiver would be
/// told the file was modified "just now". The picker does keep the content
/// URI of the original ([PlatformFile.identifier]); the provider behind it
/// knows the real time, so ask for it and stamp the copy before anything
/// else looks. Desktop pickers return the real path, and iOS's import copy
/// keeps the attribute, so elsewhere this is just `res.paths`.
Future<List<String>> pickedPaths(FilePickerResult? res) async {
  if (res == null) return const [];
  final paths = <String>[];
  for (final f in res.files) {
    final path = f.path;
    if (path == null) continue;
    paths.add(path);
    final uri = f.identifier;
    if (Platform.isAndroid && uri != null && uri.startsWith('content:')) {
      await applyReceivedMtime(
        File(path),
        await AndroidDownloadsPath.lastModifiedOf(uri),
      );
    }
  }
  return paths;
}
