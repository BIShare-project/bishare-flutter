import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

/// Pick photos and videos with the platform's gallery picker, not its file
/// manager.
///
/// `file_picker` with `FileType.media` is right on iOS (it opens PHPicker),
/// but on Android it sends `ACTION_GET_CONTENT`/`ACTION_OPEN_DOCUMENT`, which
/// is the Files app with a MIME filter — a document list, not a grid of
/// photos. Android's own gallery picker is the Photo Picker
/// (`ACTION_PICK_IMAGES`), which `image_picker` drives once opted in. Like
/// the document picker it needs no storage permission: the user chooses,
/// and the app receives only what was chosen.
///
/// Returns local paths (empty when the user cancels). On Android the Photo
/// Picker hands back copies in the app's cache, the same as the document
/// picker did, so callers treat the paths exactly as before.
Future<List<String>> pickMediaPaths({bool allowMultiple = true}) async {
  if (Platform.isAndroid) {
    final impl = ImagePickerPlatform.instance;
    // Opt-in flag: without it image_picker also falls back to the document
    // picker. Android 13+ has the Photo Picker built in; 11–12 get it through
    // Google Play services; older devices fall back to the system chooser.
    if (impl is ImagePickerAndroid) impl.useAndroidPhotoPicker = true;
    final picker = ImagePicker();
    if (allowMultiple) {
      final files = await picker.pickMultipleMedia();
      return [for (final f in files) f.path];
    }
    final file = await picker.pickMedia();
    return file == null ? const [] : [file.path];
  }
  final res = await FilePicker.platform.pickFiles(
    allowMultiple: allowMultiple,
    type: FileType.media,
  );
  return res?.paths.whereType<String>().toList() ?? const [];
}
