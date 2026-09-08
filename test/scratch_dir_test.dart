import 'dart:io';

import 'package:bishare/core/io/scratch_dir.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Stands in for path_provider on macOS, where `getTemporaryDirectory()` hands
/// back `<Caches>/<bundle-id>` — a path the plugin composes but never creates.
class _MissingTempDirProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _MissingTempDirProvider(this.path);
  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = PathProviderPlatform.instance;
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('scratch-dir-test-');
  });

  tearDown(() async {
    PathProviderPlatform.instance = original;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('appTempDir creates the directory path_provider only names', () async {
    final missing = '${root.path}/Caches/com.bishare.app';
    expect(Directory(missing).existsSync(), isFalse);
    PathProviderPlatform.instance = _MissingTempDirProvider(missing);

    final dir = await appTempDir();

    expect(dir.existsSync(), isTrue);
    expect(dir.path, missing);
  });

  test('createScratchDir works when the temp dir does not exist yet', () async {
    // The macOS regression: Secure Link and Live transfer both seal into a
    // scratch dir, and both died with PathNotFoundException here.
    PathProviderPlatform.instance =
        _MissingTempDirProvider('${root.path}/Caches/com.bishare.app');

    final scratch = await createScratchDir('bishare-e2e-');

    expect(scratch.existsSync(), isTrue);
    final f = File('${scratch.path}/sealed.bin')..writeAsBytesSync([1, 2, 3]);
    expect(f.readAsBytesSync(), [1, 2, 3]);
  });

  test('falls back to systemTemp when the plugin channel throws', () async {
    PathProviderPlatform.instance = _ThrowingProvider();

    final scratch = await createScratchDir('bishare-fallback-');

    expect(scratch.existsSync(), isTrue);
    await scratch.delete(recursive: true);
  });
}

class _ThrowingProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => throw MissingPluginException();
}
