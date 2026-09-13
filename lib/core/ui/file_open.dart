import 'dart:io' show Platform;

import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [path] with the OS default handler, cross-platform.
///
/// Android and iOS go through `open_file` (a content URI + chooser). It
/// replaced `open_filex`, whose Android FileProvider class has the same name as
/// open_file's, which universal_file_viewer depends on, so the two can't both
/// link. `open_file` has no Windows/Linux implementation, so desktop routes
/// through `url_launcher`'s file URI instead — every desktop platform has a
/// `url_launcher` implementation. Returns `true` on success; callers show
/// their own localized error on `false`. Never throws (a missing platform impl
/// degrades to `false`).
Future<bool> openFile(String path) async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final res = await OpenFile.open(path);
      return res.type == ResultType.done;
    }
    return await launchUrl(Uri.file(path));
  } on Object {
    return false;
  }
}
