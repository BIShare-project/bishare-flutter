import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/android_downloads_channel.dart';
import 'preserve_mtime.dart';

/// Pick any files and return their local paths (empty when cancelled), with
/// the original "Date modified" restored on Android. Every "choose files"
/// button goes through here so none of them loses the date.
///
/// [FilePickerAndroidOptions] (a one-off, read-only grant — nothing is
/// persisted) is what makes the plugin report each pick's original content
/// URI as [AndroidPlatformFile.safHandle]; without it there is no way back
/// to the original file. See [pickedPaths].
Future<List<String>> pickFilePaths({bool multiple = true}) async {
  const android = FilePickerAndroidOptions();
  try {
    final files = multiple
        ? await FilePicker.pickFiles(androidOptions: android)
        : [?await FilePicker.pickFile(androidOptions: android)];
    return await pickedPaths(files);
  } on PlatformException catch (e) {
    // As file_picker 10 did: a failed or overlapping pick picks nothing.
    debugPrint('[picker] pick failed: ${e.code} ${e.message}');
    return const [];
  }
}

/// The paths of picked files, with the original "Date modified" restored on
/// Android.
///
/// On Android the picker hands the app a COPY in its cache, and that copy is
/// stamped with the moment it was copied — so by the time a transfer reads
/// the file's mtime the real one is already gone, and the receiver would be
/// told the file was modified "just now". The provider behind the original
/// content URI knows the real time, so ask for it and stamp the copy before
/// anything else looks. Desktop pickers return the real path, and iOS's
/// import copy keeps the attribute, so elsewhere this is just the paths.
Future<List<String>> pickedPaths(List<PlatformFile> files) async {
  final paths = <String>[];
  for (final f in files) {
    final path = f.path;
    if (path == null) continue;
    paths.add(path);
    final uri = f is AndroidPlatformFile ? f.safHandle?.uri : null;
    if (Platform.isAndroid && uri != null && uri.scheme == 'content') {
      await applyReceivedMtime(
        File(path),
        await AndroidDownloadsPath.lastModifiedOf(uri.toString()),
      );
    }
  }
  return paths;
}
