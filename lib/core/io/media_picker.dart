import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/vault_tables.dart';

/// Removes the photo copies that iOS builds up to 2.6.3 left behind.
///
/// file_picker 10 copied every photo picked on iOS into
/// `Documents/picked_images` and never deleted it, so each send kept a full
/// duplicate (also in the iCloud backup). Its successor copies into `tmp`,
/// which iOS clears by itself. A copy that a queued Drive upload still reads
/// is kept; names are compared, not paths, because the app's container path
/// changes on every update.
Future<void> sweepLegacyPickedImages(VaultDao dao) async {
  if (!Platform.isIOS) return;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'picked_images'));
    if (!await dir.exists()) return;
    final keep = {
      for (final t in await dao.pendingTransfers())
        if (t.localPath.contains('/picked_images/')) p.basename(t.localPath),
    };
    await for (final e in dir.list()) {
      if (e is File && !keep.contains(p.basename(e.path))) await e.delete();
    }
    if (keep.isEmpty) await dir.delete(recursive: true);
  } on Object catch (e) {
    debugPrint('[media] picked_images sweep failed: $e');
  }
}

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
  // iOS: `current` hands over the original (HEIC/HEVC, EXIF intact) instead
  // of letting the system transcode, and unordered selection keeps
  // swipe-to-select in the grid, which picking hundreds of photos needs.
  const darwin = DarwinOptions(
    assetRepresentationMode: DarwinAssetRepresentationMode.current,
    orderedSelection: false,
  );
  try {
    final files = allowMultiple
        ? await FilePicker.pickFiles(type: FileType.media, darwinOptions: darwin)
        : [
            ?await FilePicker.pickFile(
              type: FileType.media,
              darwinOptions: darwin,
            ),
          ];
    return [for (final f in files) ?f.path];
  } on PlatformException catch (e) {
    // `load_failed` (photos only in iCloud while offline) and
    // `multiple_request` (a pick still open) — file_picker 10 answered both
    // with an empty list, so keep that: nothing was picked.
    debugPrint('[media] pick failed: ${e.code} ${e.message}');
    return const [];
  }
}
