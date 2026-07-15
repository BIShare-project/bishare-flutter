import 'dart:convert';

import 'package:bishare/core/sync/delta_engine.dart';
import 'package:bishare/core/sync/ignore_rules.dart';
import 'package:bishare/core/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManifestEntry', () {
    test('round-trips, omitting sha256 for dirs', () {
      const file = ManifestEntry(
        path: 'a/b.txt',
        size: 5,
        mtimeMs: 1000,
        sha256: 'abc',
      );
      final fj = file.toJson();
      expect(fj['isDir'], false);
      expect(fj['sha256'], 'abc');
      expect(ManifestEntry.fromJson(fj).path, 'a/b.txt');

      const dir = ManifestEntry(path: 'a', size: 0, mtimeMs: 900, isDir: true);
      final dj = dir.toJson();
      expect(dj.containsKey('sha256'), isFalse); // omitted when null
      expect(dj['isDir'], true);
    });
  });

  group('DeltaOp', () {
    test('parses op kinds and flags metadata-only ops', () {
      final rename = DeltaOp.fromJson({
        'op': 'rename',
        'path': 'old.txt',
        'newPath': 'new.txt',
      });
      expect(rename.kind, SyncOpKind.rename);
      expect(rename.newPath, 'new.txt');
      expect(rename.isMetadataOnly, isTrue);

      final add = DeltaOp.fromJson({
        'op': 'add',
        'path': 'x.bin',
        'sha256': 'ff',
        'size': 10,
        'isDir': false,
      });
      expect(add.kind, SyncOpKind.add);
      expect(add.isMetadataOnly, isFalse); // needs the bytes

      expect(DeltaOp.fromJson({'op': 'delete', 'path': 'g'}).isMetadataOnly, isTrue);
      // An unknown op from a newer peer is preserved as unknown, never acted on.
      expect(DeltaOp.fromJson({'op': 'chmod', 'path': 'g'}).kind, SyncOpKind.unknown);
    });
  });

  group('IgnoreRules defaults', () {
    final rules = IgnoreRules.defaults();

    test('OS cruft + temp/lock at any depth', () {
      expect(rules.isIgnored('.DS_Store'), isTrue);
      expect(rules.isIgnored('deep/nested/.DS_Store'), isTrue);
      expect(rules.isIgnored('notes.tmp'), isTrue);
      expect(rules.isIgnored('a/b/download.part'), isTrue);
      expect(rules.isIgnored(r'~$report.docx'), isTrue); // editor lock file
    });

    test('conflict copies are never re-synced', () {
      expect(
        rules.isIgnored('report.sync-conflict-20260712-143005-MacMini.docx'),
        isTrue,
      );
    });

    test('.bishare-trash/ prunes the whole subtree', () {
      expect(rules.isIgnored('.bishare-trash', isDir: true), isTrue);
      expect(rules.isIgnored('.bishare-trash/pair1/old.txt'), isTrue);
    });

    test('ordinary files are not ignored', () {
      expect(rules.isIgnored('report.docx'), isFalse);
      expect(rules.isIgnored('photos/trip.jpg'), isFalse);
      expect(rules.isIgnored('src/main.dart'), isFalse);
    });
  });

  group('IgnoreRules user patterns (.bishareignore)', () {
    final rules = IgnoreRules.withUserPatterns([
      '# comment and blank lines are skipped',
      '',
      'node_modules/', // dir prune at any depth
      '/build', // anchored to root only
      '*.log',
      '!keep.log', // negation unsupported in v1 → dropped, keep.log stays matched by *.log
    ]);

    test('directory pattern prunes at any depth', () {
      expect(rules.isIgnored('node_modules', isDir: true), isTrue);
      expect(rules.isIgnored('pkg/node_modules/lib/x.js'), isTrue);
    });

    test('anchored pattern matches only at the root', () {
      expect(rules.isIgnored('build', isDir: true), isTrue);
      expect(rules.isIgnored('sub/build', isDir: true), isFalse); // not anchored here
    });

    test('wildcard matches basename at any depth; negation is not honored (v1)', () {
      expect(rules.isIgnored('server.log'), isTrue);
      expect(rules.isIgnored('logs/app/today.log'), isTrue);
      expect(rules.isIgnored('keep.log'), isTrue); // '!' line was dropped
    });

    test('builtins still apply alongside user patterns', () {
      expect(rules.isIgnored('.DS_Store'), isTrue);
    });
  });

  group('DeltaEngine', () {
    test('encodes both manifests and parses the ops (injected diff)', () async {
      String? seenLocal;
      String? seenRemote;
      final engine = DeltaEngine(
        diff: ({required localJson, required remoteJson}) async {
          seenLocal = localJson;
          seenRemote = remoteJson;
          return jsonEncode([
            {'op': 'add', 'path': 'new.txt', 'sha256': 'aa', 'size': 3, 'isDir': false},
            {'op': 'delete', 'path': 'gone.txt'},
          ]);
        },
      );

      final ops = await engine.diff(
        local: const [ManifestEntry(path: 'gone.txt', size: 1, mtimeMs: 1, sha256: 'zz')],
        remote: const [ManifestEntry(path: 'new.txt', size: 3, mtimeMs: 2, sha256: 'aa')],
      );

      // The engine handed the FFI exactly the manifests it was given.
      expect(jsonDecode(seenLocal!)[0]['path'], 'gone.txt');
      expect(jsonDecode(seenRemote!)[0]['path'], 'new.txt');

      // ...and mapped the JSON result into typed ops.
      expect(ops.map((o) => o.kind), [SyncOpKind.add, SyncOpKind.delete]);
      expect(ops.first.sha256, 'aa');
      expect(ops.last.isMetadataOnly, isTrue);
    });

    test('tolerates a non-list diff result', () async {
      final engine = DeltaEngine(
        diff: ({required localJson, required remoteJson}) async => '{}',
      );
      expect(await engine.diff(local: const [], remote: const []), isEmpty);
    });
  });
}
