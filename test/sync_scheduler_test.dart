import 'dart:async';
import 'dart:io';

import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/sync/folder_watcher.dart';
import 'package:bishare/features/folder_sync/data/sync_scheduler.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watcher/watcher.dart';

/// A hand-driven DirectoryWatcher: tests push [WatchEvent]s into [emit].
class FakeDirWatcher implements DirectoryWatcher {
  FakeDirWatcher(this.path);

  @override
  final String path;
  final _events = StreamController<WatchEvent>.broadcast();

  void emit() =>
      _events.add(WatchEvent(ChangeType.MODIFY, '$path/some-file'));

  @override
  Stream<WatchEvent> get events => _events.stream;

  @override
  String get directory => path;

  @override
  bool get isReady => true;

  @override
  Future<void> get ready async {}
}

DiscoveredDevice _device(String fp) => DiscoveredDevice(
      fingerprint: fp,
      alias: fp,
      host: '198.18.0.1',
      port: 1,
      lastSeen: DateTime(2026, 1, 1),
      firstSeen: DateTime(2026, 1, 1),
    );

void main() {
  late AppDatabase db;
  late StreamController<List<DiscoveredDevice>> devices;
  late List<DiscoveredDevice> online;
  late List<(String pairId, String peerFp)> runs;
  late Map<String, FakeDirWatcher> fakes;
  late SyncScheduler scheduler;

  Future<void> pump([int ms = 50]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    devices = StreamController<List<DiscoveredDevice>>.broadcast();
    online = [];
    runs = [];
    fakes = {};
    scheduler = SyncScheduler(
      (pair, peer) async => runs.add((pair.id, peer.fingerprint)),
      db.syncDao,
      deviceStream: devices.stream,
      currentDevices: () => online,
      watcherFactory: (root) => FolderWatcher(
        root,
        debounce: const Duration(milliseconds: 30),
        factory: (path) => fakes.putIfAbsent(path, () => FakeDirWatcher(path)),
      ),
    )..start();
  });

  tearDown(() async {
    await scheduler.dispose();
    await devices.close();
    await db.close();
  });

  Future<void> addPair(String id, String peerFp, {bool paused = false}) async {
    await db.syncDao.createPair(
      SyncPairsCompanion.insert(
        id: id,
        rootPath: '/root/$id',
        peerFingerprint: peerFp,
        peerPublicKey: const Value('pk'),
        createdAt: DateTime(2026, 1, 1),
        paused: Value(paused),
      ),
      id,
    );
    await pump();
  }

  test('a debounced burst of file events triggers ONE sync to the online peer',
      () async {
    online = [_device('fp-peer')];
    await addPair('p1', 'fp-peer');

    final fake = fakes['/root/p1']!;
    fake.emit();
    fake.emit();
    fake.emit(); // burst
    await pump(80); // > debounce

    expect(runs, [('p1', 'fp-peer')], reason: 'burst collapses to one run');
  });

  test('no run while the peer is offline; peer-online flushes the pair',
      () async {
    await addPair('p1', 'fp-peer'); // peer NOT in `online`

    fakes['/root/p1']!.emit();
    await pump(80);
    expect(runs, isEmpty, reason: 'offline peer → nothing to sync against');

    // Peer appears on the LAN.
    online = [_device('fp-peer')];
    devices.add(online);
    await pump();
    expect(runs, [('p1', 'fp-peer')], reason: 'presence flushes the pair');
  });

  test('a paused pair never watches nor triggers; resume re-arms it', () async {
    online = [_device('fp-peer')];
    await addPair('p1', 'fp-peer', paused: true);
    expect(fakes, isEmpty, reason: 'paused pair gets no watcher');

    devices.add(online); // presence event
    await pump();
    expect(runs, isEmpty);

    await db.syncDao.setPaused('p1', false);
    await pump();
    expect(fakes.containsKey('/root/p1'), isTrue, reason: 'resume arms watcher');
    fakes['/root/p1']!.emit();
    await pump(80);
    expect(runs, [('p1', 'fp-peer')]);
  });

  test('a failing runner is contained and later triggers still fire', () async {
    // Rebuild the scheduler with a runner whose RUNTIME future carries a value
    // type and THROWS — the regression that produced "the error handler of
    // Future.catchError must return a value of the future's type" on device.
    await scheduler.dispose();
    var calls = 0;
    scheduler = SyncScheduler(
      (pair, peer) async {
        calls++;
        if (calls == 1) throw StateError('peer went away mid-sync');
      },
      db.syncDao,
      deviceStream: devices.stream,
      currentDevices: () => online,
      watcherFactory: (root) => FolderWatcher(
        root,
        debounce: const Duration(milliseconds: 30),
        factory: (path) => fakes.putIfAbsent(path, () => FakeDirWatcher(path)),
      ),
    )..start();

    online = [_device('fp-peer')];
    await addPair('p1', 'fp-peer');

    fakes['/root/p1']!.emit();
    await pump(80); // first run throws — must be swallowed, not unhandled
    expect(calls, 1);

    fakes['/root/p1']!.emit();
    await pump(80);
    expect(calls, 2, reason: 'a failure must not wedge future triggers');
  });

  test('cloud: offline peer + lanCloud → push; poll tick pulls', () async {
    await scheduler.dispose();
    final pushes = <String>[];
    final pulls = <String>[];
    scheduler = SyncScheduler(
      (pair, peer) async => runs.add((pair.id, peer.fingerprint)),
      db.syncDao,
      deviceStream: devices.stream,
      currentDevices: () => online, // peer stays OFFLINE
      cloudPush: (pair) async => pushes.add(pair.id),
      cloudPull: (pair) async => pulls.add(pair.id),
      cloudPollEvery: const Duration(milliseconds: 60),
      watcherFactory: (root) => FolderWatcher(
        root,
        debounce: const Duration(milliseconds: 30),
        factory: (path) => fakes.putIfAbsent(path, () => FakeDirWatcher(path)),
      ),
    )..start();

    await db.syncDao.createPair(
      SyncPairsCompanion.insert(
        id: 'pc',
        rootPath: '/root/pc',
        peerFingerprint: 'fp-away',
        peerPublicKey: const Value('pk'),
        mode: const Value('lanCloud'),
        createdAt: DateTime(2026, 1, 1),
      ),
      'pc',
    );
    await pump();

    // A change with the peer away goes to the cloud, not the LAN.
    fakes['/root/pc']!.emit();
    await pump(80);
    expect(runs, isEmpty);
    expect(pushes, ['pc']);

    // The poll tick pulls for lanCloud pairs.
    await pump(80);
    expect(pulls, isNotEmpty);

    // A lanOnly pair triggers NEITHER path while its peer is away.
    await db.syncDao.setMode('pc', 'lanOnly');
    await pump();
    pushes.clear();
    fakes['/root/pc']!.emit();
    await pump(80);
    expect(pushes, isEmpty, reason: 'lanOnly never touches the cloud');
  });

  test('stale presence: LAN failure falls back to cloud push (lanCloud only)',
      () async {
    await scheduler.dispose();
    final pushes = <String>[];
    scheduler = SyncScheduler(
      (pair, peer) async => throw const SocketException('timed out'),
      db.syncDao,
      deviceStream: devices.stream,
      currentDevices: () => online, // peer LOOKS online (stale mDNS)
      cloudPush: (pair) async => pushes.add(pair.id),
      cloudPull: (pair) async {},
      watcherFactory: (root) => FolderWatcher(
        root,
        debounce: const Duration(milliseconds: 30),
        factory: (path) => fakes.putIfAbsent(path, () => FakeDirWatcher(path)),
      ),
    )..start();

    online = [_device('fp-peer')];
    await addPair('pl', 'fp-peer'); // lanOnly default
    await db.syncDao.setMode('pl', 'lanCloud');
    await pump();

    fakes['/root/pl']!.emit();
    await pump(120);
    expect(pushes, ['pl'], reason: 'LAN timeout must hand off to the cloud');

    // lanOnly pair: failure stays failed — never the cloud.
    await db.syncDao.setMode('pl', 'lanOnly');
    await pump();
    pushes.clear();
    fakes['/root/pl']!.emit();
    await pump(120);
    expect(pushes, isEmpty);
  });

  test('deleting a pair tears its watcher down', () async {
    online = [_device('fp-peer')];
    await addPair('p1', 'fp-peer');
    expect(fakes['/root/p1']!, isNotNull);
    final watcherStopped = fakes['/root/p1']!;

    await db.syncDao.deletePair('p1');
    await pump();
    watcherStopped.emit(); // stale event after teardown
    await pump(80);
    expect(runs, isEmpty, reason: 'no trigger after the pair is gone');
  });
}
