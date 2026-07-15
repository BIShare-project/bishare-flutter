import 'package:bishare/core/sync/sync_roots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final r = SyncRootResolver(
    saveDirPath: () => '/Users/me/Desktop/BIShare',
    docsDirPath: () =>
        '/var/mobile/Containers/Data/Application/NEW-UUID/Documents',
  );

  test('paths under the save location round-trip through @save/', () {
    const abs = '/Users/me/Desktop/BIShare/BIShare Sync/Docs';
    final stored = r.toPortable(abs);
    expect(stored, '@save/BIShare Sync/Docs');
    expect(r.resolve(stored), abs);
  });

  test('the save location itself round-trips', () {
    final stored = r.toPortable('/Users/me/Desktop/BIShare');
    expect(stored, '@save/');
    expect(r.resolve(stored), '/Users/me/Desktop/BIShare');
  });

  test('paths under docs round-trip through @docs/', () {
    const abs =
        '/var/mobile/Containers/Data/Application/NEW-UUID/Documents/Notes';
    expect(r.toPortable(abs), '@docs/Notes');
    expect(r.resolve('@docs/Notes'), abs);
  });

  test('an external folder stays absolute both ways', () {
    const abs = '/Volumes/External/Projects';
    expect(r.toPortable(abs), abs);
    expect(r.resolve(abs), abs);
  });

  test('resolve follows the LIVE save location (setting changed later)', () {
    var save = '/old/base';
    final live = SyncRootResolver(
      saveDirPath: () => save,
      docsDirPath: () => '/docs',
    );
    final stored = live.toPortable('/old/base/BIShare Sync/X');
    expect(stored, '@save/BIShare Sync/X');
    save = '/new/base';
    expect(live.resolve(stored), '/new/base/BIShare Sync/X');
  });

  test('LEGACY absolute iOS container path auto-heals onto the current docs',
      () {
    // A pair stored before the portable scheme — or before a reinstall changed
    // the container UUID. iOS migrates the files; the path must re-base.
    const legacy =
        '/var/mobile/Containers/Data/Application/OLD-DEAD-UUID/Documents/BIShare/BIShare Sync/Foo';
    expect(
      r.resolve(legacy),
      '/var/mobile/Containers/Data/Application/NEW-UUID/Documents/BIShare/BIShare Sync/Foo',
    );
    // Simulator flavor with /private prefix heals too.
    const sim =
        '/private/var/mobile/Containers/Data/Application/OLD/Documents/X';
    expect(
      r.resolve(sim),
      '/var/mobile/Containers/Data/Application/NEW-UUID/Documents/X',
    );
  });

  test('a current-container absolute path is left intact by resolve', () {
    const current =
        '/var/mobile/Containers/Data/Application/NEW-UUID/Documents/Keep';
    expect(r.resolve(current), current);
  });
}
