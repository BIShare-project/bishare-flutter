import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A private scratch directory for transient bytes (a sealed upload body, a
/// live-transfer ciphertext). The platform temp dir when the plugin channel
/// is available; `Directory.systemTemp` otherwise (unit tests, or a platform
/// without the channel). Callers delete it when they are done.
Future<Directory> createScratchDir(String prefix) async {
  Directory base;
  try {
    base = await getTemporaryDirectory();
  } on Object {
    base = Directory.systemTemp;
  }
  return base.createTemp(prefix);
}
