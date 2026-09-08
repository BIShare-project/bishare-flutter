import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The platform temp directory, guaranteed to exist.
///
/// On macOS `getTemporaryDirectory()` returns `<Caches>/<bundle-id>` — a path
/// path_provider *builds* but never creates, because a sandboxed app is
/// expected to make its own subdirectory. Until something does, every write
/// into it throws `PathNotFoundException`, which took out Secure Link, Live
/// transfer, and every "send text / contact / folder" source on macOS.
/// iOS is unaffected (the plugin skips the bundle-id suffix there), and
/// Windows, Linux and Android hand back a directory that already exists.
Future<Directory> appTempDir() async {
  try {
    final base = await getTemporaryDirectory();
    await base.create(recursive: true); // no-op when it is already there
    return base;
  } on Object {
    return Directory.systemTemp; // no plugin channel (unit tests) — still usable
  }
}

/// A private scratch directory for transient bytes (a sealed upload body, a
/// live-transfer ciphertext). Callers delete it when they are done.
Future<Directory> createScratchDir(String prefix) async {
  final base = await appTempDir();
  try {
    return await base.createTemp(prefix);
  } on Object {
    return Directory.systemTemp.createTemp(prefix);
  }
}
