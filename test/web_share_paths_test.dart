import 'dart:io';

import 'package:bishare/core/server/web_share_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Path-traversal hardening for the browser Web-Share endpoints
/// (`/api/v1/browse`, `/download-folder`, `/api/v1/download-file`): a
/// browser-supplied `?path=` must never resolve outside the share root.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bishare_paths_test');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('empty path resolves to the root itself', () {
    final resolved = WebSharePaths.resolveUnder(root, '');
    expect(resolved, isNotNull);
    expect(p.equals(resolved!, root.path), isTrue);
  });

  test('plain nested paths resolve inside the root', () {
    final resolved = WebSharePaths.resolveUnder(root, 'Images/Sub folder');
    expect(resolved, isNotNull);
    expect(p.isWithin(root.path, resolved!), isTrue);
    expect(resolved, endsWith('Sub folder'));
  });

  test('traversal segments are rejected', () {
    expect(WebSharePaths.resolveUnder(root, '..'), isNull);
    expect(WebSharePaths.resolveUnder(root, '../'), isNull);
    expect(WebSharePaths.resolveUnder(root, '../../etc/passwd'), isNull);
    expect(WebSharePaths.resolveUnder(root, 'Images/../..'), isNull);
    expect(WebSharePaths.resolveUnder(root, 'Images/../../other'), isNull);
    expect(WebSharePaths.resolveUnder(root, '.'), isNull);
    expect(WebSharePaths.resolveUnder(root, 'Images/./x'), isNull);
  });

  test('absolute paths are rejected', () {
    expect(WebSharePaths.resolveUnder(root, '/etc/passwd'), isNull);
    expect(WebSharePaths.resolveUnder(root, '/${root.path}'), isNull);
    expect(WebSharePaths.resolveUnder(root, 'C:whatever'), isNull);
    expect(WebSharePaths.resolveUnder(root, r'C:\Windows'), isNull);
  });

  test('backslashes and NUL are rejected', () {
    expect(WebSharePaths.resolveUnder(root, r'a\..\b'), isNull);
    expect(WebSharePaths.resolveUnder(root, r'\\server\share'), isNull);
    expect(WebSharePaths.resolveUnder(root, 'a\u0000b'), isNull);
  });

  test('names with ordinary spaces stay valid', () {
    expect(
      WebSharePaths.resolveUnder(root, 'My Folder/file (1).txt'),
      isNotNull,
    );
  });

  test('hidden segments (dotfiles, .part temps) are rejected', () {
    expect(WebSharePaths.resolveUnder(root, '.browser-x.part'), isNull);
    expect(WebSharePaths.resolveUnder(root, 'Images/.hidden'), isNull);
  });

  test('double slashes collapse without escaping the root', () {
    final resolved = WebSharePaths.resolveUnder(root, 'Images//x');
    expect(resolved, isNotNull);
    expect(p.isWithin(root.path, resolved!), isTrue);
  });

  test('contains() accepts the root and its children only', () {
    expect(WebSharePaths.contains(root, root.path), isTrue);
    expect(WebSharePaths.contains(root, p.join(root.path, 'x')), isTrue);
    expect(WebSharePaths.contains(root, p.dirname(root.path)), isFalse);
    expect(WebSharePaths.contains(root, '/etc'), isFalse);
  });
}
