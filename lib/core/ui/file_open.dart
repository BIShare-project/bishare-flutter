import 'dart:io' show Platform;

import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [path] with the OS default handler, cross-platform.
///
/// `open_filex` only ships an implementation on Android and iOS, so calling it
/// on desktop (macOS/Windows/Linux) throws `MissingPluginException`. On desktop
/// we route through `url_launcher`'s file URI instead — every desktop platform
/// has a `url_launcher` implementation. Returns `true` on success; callers show
/// their own localized error on `false`. Never throws (a missing platform impl
/// degrades to `false`).
Future<bool> openFile(String path) async {
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final res = await OpenFilex.open(path);
      return res.type == ResultType.done;
    }
    return await launchUrl(Uri.file(path));
  } on Object {
    return false;
  }
}
