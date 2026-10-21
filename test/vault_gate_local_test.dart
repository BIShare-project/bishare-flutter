import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:flutter_test/flutter_test.dart';

import 'helpers/rust_test_lib.dart';
import 'helpers/vault_local.dart';

/// drive-plan.md phase 4 gate, against a LOCAL Drive worker (never
/// production), one part per name in VAULT_GATE:
///
///   small    a folder of 10,000 small files goes up from one device and
///            comes back byte-identical on another
///   big      one file of VAULT_GATE_BIG_GB gigabytes (20 by default) goes
///            up, is cut off part way, resumes without sending finished parts
///            again, and comes back byte-identical
///   offline  two devices that changed things without seeing each other
///            (uploads queued with the server out of reach, then changes made
///            on indexes that are behind) end up with the same index
///   share    a shared file opens from its link, and the Drive copy is still
///            there after the link expired and the hourly purge ran
///
///   VAULT_LOCAL_API=http://localhost:8799 \
///   VAULT_MINT=~/Documents/bishare-project/regression-tools/vault_mint_token.mjs \
///   VAULT_LOCAL_D1=`the worker's local D1 .sqlite file, for "share"` \
///   VAULT_GATE=small,big,offline,share \
///   flutter test test/vault_gate_local_test.dart
///
/// "big" needs about three times the file's size free on disk (the sealed
/// copy, the worker's R2 copy, the download) and refuses to start without it.
void main() {
  final api = Platform.environment['VAULT_LOCAL_API'];
  final mint = Platform.environment['VAULT_MINT'];
  final parts = (Platform.environment['VAULT_GATE'] ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .toSet();
  if (api == null || mint == null || parts.isEmpty) {
    test(
      'Drive gate skipped: VAULT_LOCAL_API / VAULT_MINT / VAULT_GATE not set',
      () {},
    );
    return;
  }
  if (!RegExp(r'^http://(localhost|127\.0\.0\.1):\d+$').hasMatch(api)) {
    throw StateError('VAULT_LOCAL_API must be a localhost URL');
  }

  late bool rust;
  late Directory tmp;
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    rust = await initRustForTests();
    tmp = await Directory.systemTemp.createTemp('vault_gate');
  });
  tearDownAll(() => tmp.delete(recursive: true));

  /// Two devices of one new account, both with the key.
  Future<(VaultLocalDevice, VaultLocalDevice)> pair(String tag) async {
    final subject = 'gate-$tag-${DateTime.now().microsecondsSinceEpoch}';
    final dir = await Directory('${tmp.path}/$tag').create(recursive: true);
    final a = await VaultLocalDevice.signIn('a', api, mint, subject, dir);
    final b = await VaultLocalDevice.signIn('b', api, mint, subject, dir);
    await b.account.acceptPhrase((await a.account.phrase())!);
    expect(
      [a.account.status, b.account.status],
      [VaultStatus.ready, VaultStatus.ready],
    );
    return (a, b);
  }

  /// Everything an index holds that both devices must agree on.
  Future<List<String>> snapshot(VaultLocalDevice d) async {
    await d.sync.pull();
    final rows = await d.db.select(d.db.vaultObjects).get();
    return [
      for (final o in rows)
        [
          o.id,
          o.parent ?? '-',
          o.name,
          o.kind,
          o.blobId ?? '-',
          o.trashedAt == null ? 'live' : 'trash',
        ].join('|'),
    ]..sort();
  }

  Future<Uint8List> sha(File f) async =>
      Uint8List.fromList((await sha256.bind(f.openRead()).first).bytes);

  test(
    '10,000 small files go up and come back byte-identical',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final (a, b) = await pair('small');
      final rng = Random(10000);
      final src = Directory('${tmp.path}/small-src/Ten thousand');
      final hashes = <String, Uint8List>{};
      for (var f = 0; f < 100; f++) {
        final d = await Directory(
          '${src.path}/folder ${f.toString().padLeft(3, '0')}',
        ).create(recursive: true);
        for (var i = 0; i < 100; i++) {
          final size = 200 + rng.nextInt(3800);
          final bytes = Uint8List.fromList(
            List.generate(size, (_) => rng.nextInt(256)),
          );
          final file = File(
            '${d.path}/file ${i.toString().padLeft(3, '0')}.bin',
          )..writeAsBytesSync(bytes);
          hashes['${d.uri.pathSegments[d.uri.pathSegments.length - 2]}/${file.uri.pathSegments.last}'] =
              Uint8List.fromList(sha256.convert(bytes).bytes);
        }
      }
      final up = Stopwatch()..start();
      final queued = await a.uploader.enqueueFolder(src, a.files);
      expect(queued, 10000);
      // wrangler dev itself gives out now and then under this load; its
      // supervisor starts it again and the queue goes on where it stopped.
      var rounds = 0;
      do {
        await _waitForWorker(api);
        await a.uploader.run();
        rounds++;
      } while ((await a.db.vaultDao.pendingTransfers()).isNotEmpty &&
          rounds < 50);
      up.stop();
      expect(await a.failed(), isEmpty);
      expect(await a.db.vaultDao.pendingTransfers(), isEmpty);
      debugPrint(
        '[gate] 10,000 files up in ${up.elapsed.inSeconds} s ($rounds runs of the queue)',
      );

      final seen = await snapshot(b);
      expect(seen.where((r) => r.contains('|file|')), hasLength(10000));
      expect(seen.where((r) => r.contains('|dir|')), hasLength(101));
      final top = (await b.db.vaultDao.watchChildren(null).first).single;
      expect(top.name, 'Ten thousand');
      // Every file, one by one, as Open and Save do; a lost worker is waited for.
      final rows = await b.db.select(b.db.vaultObjects).get();
      final folders = {
        for (final o in rows)
          if (o.kind == 'dir') o.id: o.name,
      };
      final down = Stopwatch()..start();
      var same = 0;
      for (final o in rows) {
        if (o.kind != 'file') continue;
        final key = '${folders[o.parent]}/${o.name}';
        final target = File('${tmp.path}/small-out/$key');
        for (var attempt = 0; ; attempt++) {
          try {
            await b.downloader.download(o.id, target);
            break;
          } on Object catch (e) {
            if (attempt >= 5) rethrow;
            debugPrint('[gate] download of $key: $e; again');
            await _waitForWorker(api);
          }
        }
        if (listEquals(await sha(target), hashes[key])) same++;
        await target.delete();
      }
      down.stop();
      debugPrint('[gate] 10,000 files down in ${down.elapsed.inSeconds} s');
      expect(same, 10000, reason: 'every file byte-identical');
    },
    skip: !parts.contains('small'),
    timeout: const Timeout(Duration(hours: 2)),
  );

  test(
    'one big file, cut off part way, resumed, back byte-identical',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final gb = int.parse(Platform.environment['VAULT_GATE_BIG_GB'] ?? '20');
      final size = gb * 1000 * 1000 * 1000;
      final free = await _freeBytes(tmp.path);
      if (free < size * 3 + (5 << 30)) {
        fail(
          '"big" needs ${(size * 3) >> 30} GiB and 5 GiB to spare; ${free >> 30} GiB are free',
        );
      }
      var (a, b) = await pair('big');
      await a.entitle('drive_100gb_monthly');

      // A sparse file: no disk for the source, the same bytes for everyone.
      final src = File('${tmp.path}/big.bin');
      final raf = await src.open(mode: FileMode.write);
      await raf.truncate(size);
      await raf.close();
      final want = await sha(src);

      a.failPutsAfter = a.puts + 30;
      await a.uploader.enqueue([src]);
      await a.uploader.run();
      final stuck = (await a.db.vaultDao.pendingTransfers()).single;
      expect(
        stuck.partsDone,
        contains('"n":30'),
        reason: 'thirty parts went up before the cut',
      );
      final sent = a.puts;
      a = a.restart();
      final up = Stopwatch()..start();
      await a.uploader.run();
      up.stop();
      expect(await a.failed(), isEmpty);
      final row = (await a.db.vaultDao.watchChildren(null).first).single;
      final parts = (row.blobSize! / (100 * 1024 * 1024)).ceil();
      expect(
        a.puts - sent,
        parts - 30,
        reason: 'only the parts not sent before',
      );
      debugPrint(
        '[gate] $gb GB up (after the cut) in ${up.elapsed.inSeconds} s; ${(await _freeBytes(tmp.path)) >> 30} GiB free',
      );

      await b.sync.pull();
      final down = Stopwatch()..start();
      final out = await b.downloader.download(
        row.id,
        File('${tmp.path}/big-out.bin'),
      );
      down.stop();
      debugPrint('[gate] $gb GB down in ${down.elapsed.inSeconds} s');
      expect(await out.length(), size);
      expect(await sha(out), want, reason: 'byte-identical');
      await out.delete();
      await src.delete();
    },
    skip: !parts.contains('big'),
    timeout: const Timeout(Duration(hours: 3)),
  );

  test(
    'two devices that changed things apart end up identical',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      var (a, b) = await pair('offline');
      final rng = Random(2);
      File make(String name) => File('${tmp.path}/offline-src/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(
          Uint8List.fromList(List.generate(5000, (_) => rng.nextInt(256))),
        );

      // No network for either: what they add waits in their queues.
      a = a.at('http://127.0.0.1:9');
      b = b.at('http://127.0.0.1:9');
      await a.uploader.enqueue([make('a-1.bin'), make('notes.txt')]);
      await b.uploader.enqueue([make('b-1.bin'), make('notes2.txt')]);
      await a.uploader.run();
      await b.uploader.run();
      expect((await a.db.vaultDao.pendingTransfers()).length, 2);
      expect((await b.db.vaultDao.pendingTransfers()).length, 2);

      // Back online, one after the other, neither having pulled first.
      a = a.restart().at(api);
      b = b.restart().at(api);
      await a.uploader.run();
      await b.uploader.run();
      expect([...await a.failed(), ...await b.failed()], isEmpty);

      // Changes on indexes that are behind: both rename the same file, one
      // trashes what the other moves, both make a folder of the same name.
      await a.sync.pull();
      await b.sync.pull();
      final shared = (await a.db.vaultDao.watchChildren(null).first).firstWhere(
        (o) => o.name == 'a-1.bin',
      );
      final other = (await a.db.vaultDao.watchChildren(null).first).firstWhere(
        (o) => o.name == 'b-1.bin',
      );
      await a.files.rename(shared.id, 'from a.bin');
      final folderB = await b.files.mkdir('Together');
      await a.files.mkdir('Together');
      await b.files.rename(shared.id, 'from b.bin');
      await a.files.trash([other.id]);
      await b.files.move([other.id], folderB);

      final sa = await snapshot(a);
      final sb = await snapshot(b);
      expect(sa, sb, reason: 'the same index on both');
      expect(
        sa.where((r) => r.contains('|Together|')),
        hasLength(2),
        reason: 'two folders of one name, both kept',
      );
    },
    skip: !parts.contains('offline'),
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'a shared file opens from its link; the Drive copy outlives the link',
    () async {
      if (!rust) return markTestSkipped(rustUnavailableReason);
      final d1 = Platform.environment['VAULT_LOCAL_D1'];
      if (d1 == null || !File(d1).existsSync()) {
        fail('set VAULT_LOCAL_D1 to the worker\'s local D1 file');
      }
      final (a, b) = await pair('share');
      final rng = Random(3);
      final src = File('${tmp.path}/share.bin')
        ..writeAsBytesSync(
          Uint8List.fromList(List.generate(3 << 20, (_) => rng.nextInt(256))),
        );
      await a.uploader.enqueue([src]);
      await a.uploader.run();
      await a.sync.pull();
      final row = (await a.db.vaultDao.watchChildren(null).first).single;
      final link = await a.shares.share(row.id, hours: 6);
      final code = Uri.parse(link.url).pathSegments.last;
      final dio = Dio(BaseOptions(baseUrl: api, validateStatus: (_) => true));
      final before = await dio.get<List<int>>(
        '/api/v1/transfer/download/$code',
        options: Options(responseType: ResponseType.bytes),
      );
      expect(before.statusCode, 200, reason: 'the link opens');

      // The link runs out and the hourly purge removes it.
      final expire = await Process.run('sqlite3', [
        d1,
        "UPDATE transfers SET expires_at = '2000-01-01T00:00:00.000Z' WHERE code = '${code.replaceAll('-', '')}'",
      ]);
      expect(expire.exitCode, 0, reason: '${expire.stderr}');
      await dio.get<Object?>(
        '/__scheduled',
        queryParameters: {'cron': '0 * * * *'},
      );
      final after = await dio.get<Object?>('/api/v1/transfer/status/$code');
      expect(after.statusCode, isNot(200), reason: 'the link is gone');

      await b.sync.pull();
      final got = await b.downloader.download(
        row.id,
        File('${tmp.path}/share-out.bin'),
      );
      expect(
        await sha(got),
        await sha(src),
        reason: 'the Drive copy is still whole',
      );
    },
    skip: !parts.contains('share'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// Until the worker answers (its supervisor may be starting it again).
Future<void> _waitForWorker(String api) async {
  final dio = Dio(BaseOptions(baseUrl: api, validateStatus: (_) => true));
  for (var i = 0; i < 120; i++) {
    try {
      if ((await dio.get<Object?>('/health')).statusCode == 200) return;
    } on Object {
      // Not up yet.
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw StateError('the local worker did not come back');
}

Future<int> _freeBytes(String path) async {
  final r = await Process.run('df', ['-k', path]);
  final line = (r.stdout as String)
      .trim()
      .split('\n')
      .last
      .split(RegExp(r'\s+'));
  return int.parse(line[3]) * 1024;
}
