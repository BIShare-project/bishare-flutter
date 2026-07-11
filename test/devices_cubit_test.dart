import 'dart:async';

import 'package:bishare/core/devices/device_registry.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/devices/presentation/devices_cubit.dart';
import 'package:bishare/features/history/data/history_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

KnownDeviceView _view(
  String fingerprint, {
  String? alias,
  bool online = false,
  DateTime? lastSeen,
  String? customName,
  bool favorite = false,
  String? model,
  String? ip,
}) => KnownDeviceView(
  fingerprint: fingerprint,
  alias: alias ?? fingerprint,
  deviceModel: model,
  deviceType: 'mobile',
  isOnline: online,
  lastSeen: lastSeen ?? DateTime(2026, 1, 1),
  lastIp: ip,
  isFavorite: favorite,
  customName: customName,
);

void main() {
  late AppDatabase db;
  late HistoryRepository history;
  late StreamController<List<KnownDeviceView>> roster;
  late DevicesCubit cubit;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    history = HistoryRepository(db);
    roster = StreamController<List<KnownDeviceView>>.broadcast();
    cubit = DevicesCubit.fromStream(roster.stream, const [], history, db);
  });

  tearDown(() async {
    await cubit.close();
    await roster.close();
    await db.close();
  });

  test('roster stream drives state; sections split online vs known', () async {
    roster.add([
      _view('a', online: true),
      _view('b'),
      _view('c', online: true),
    ]);
    await pumpEventQueue();

    expect(cubit.state.all.length, 3);
    expect(
      cubit.state.onlineNow.map((d) => d.fingerprint),
      unorderedEquals(['a', 'c']),
    );
    expect(cubit.state.knownOffline.map((d) => d.fingerprint), ['b']);
  });

  test('search matches display name, alias, model, and ip', () async {
    roster.add([
      _view('fp1', alias: 'Pixel 9', model: 'Pixel'),
      _view('fp2', alias: 'MacBook', customName: 'Work Mac', ip: '192.168.1.7'),
      _view('fp3', alias: 'iPhone', model: 'iPhone 17'),
    ]);
    await pumpEventQueue();

    cubit.setQuery('work');
    expect(cubit.state.filtered.map((d) => d.fingerprint), ['fp2']);

    // The custom name shadows nothing: the wire alias still matches.
    cubit.setQuery('macbook');
    expect(cubit.state.filtered.map((d) => d.fingerprint), ['fp2']);

    cubit.setQuery('iphone 17'); // model
    expect(cubit.state.filtered.map((d) => d.fingerprint), ['fp3']);

    cubit.setQuery('192.168.1.7'); // last ip
    expect(cubit.state.filtered.map((d) => d.fingerprint), ['fp2']);

    cubit.setQuery('nothing-matches');
    expect(cubit.state.filtered, isEmpty);

    cubit.setQuery('');
    expect(cubit.state.filtered.length, 3);
  });

  test('sort: online-first, last-seen, and name orders', () async {
    roster.add([
      _view('old', alias: 'Zed', lastSeen: DateTime(2026, 1, 1)),
      _view('new', alias: 'Mid', lastSeen: DateTime(2026, 3, 1)),
      _view(
        'live',
        alias: 'Alpha',
        online: true,
        lastSeen: DateTime(2026, 2, 1),
      ),
    ]);
    await pumpEventQueue();

    // Default: online first, then most recently seen.
    expect(
      cubit.state.filtered.map((d) => d.fingerprint),
      ['live', 'new', 'old'],
    );

    cubit.setSort(DeviceSort.lastSeen);
    expect(
      cubit.state.filtered.map((d) => d.fingerprint),
      ['new', 'live', 'old'],
    );

    cubit.setSort(DeviceSort.name);
    expect(
      cubit.state.filtered.map((d) => d.alias),
      ['Alpha', 'Mid', 'Zed'],
    );
  });

  test('display name prefers custom name; name sort uses it', () async {
    roster.add([
      _view('fp1', alias: 'Zebra Phone', customName: 'Anna'),
      _view('fp2', alias: 'Beta Pad'),
    ]);
    await pumpEventQueue();

    expect(cubit.state.all.first.displayName, isNotEmpty);
    cubit.setSort(DeviceSort.name);
    expect(cubit.state.filtered.map((d) => d.fingerprint), ['fp1', 'fp2']);
  });

  test('statsFor folds history by fingerprint (counts, bytes, last)', () async {
    Future<void> record({
      required String file,
      required int size,
      required String dir,
      required String fp,
      required DateTime at,
    }) => db.insertRecord(
      TransferRecordsCompanion.insert(
        fileName: file,
        fileSize: size,
        direction: dir,
        deviceAlias: 'peer',
        timestamp: at,
        deviceFingerprint: Value(fp),
      ),
    );

    await record(
      file: 'a.jpg',
      size: 100,
      dir: 'sent',
      fp: 'fp1',
      at: DateTime(2026, 1, 1),
    );
    await record(
      file: 'b.mp4',
      size: 250,
      dir: 'received',
      fp: 'fp1',
      at: DateTime(2026, 1, 3),
    );
    await record(
      file: 'c.pdf',
      size: 999,
      dir: 'sent',
      fp: 'other',
      at: DateTime(2026, 1, 2),
    );

    final stats = await cubit.statsFor('fp1');
    expect(stats.sentCount, 1);
    expect(stats.sentBytes, 100);
    expect(stats.receivedCount, 1);
    expect(stats.receivedBytes, 250);
    expect(stats.lastTransfer?.fileName, 'b.mp4'); // newest fp1 row

    final none = await cubit.statsFor('unknown');
    expect(none.isEmpty, isTrue);
    expect(none.lastTransfer, isNull);
  });

  test('remove forgets the roster row and the favorite', () async {
    await db.upsertKnownDevice(
      KnownDevicesCompanion.insert(
        fingerprint: 'fp1',
        alias: 'Phone',
        lastSeen: DateTime(2026, 1, 1),
      ),
    );
    await db.upsertFavorite(
      FavoriteDevicesCompanion.insert(
        fingerprint: 'fp1',
        addedAt: DateTime(2026, 1, 1),
      ),
    );

    await cubit.remove('fp1');

    expect(await db.watchKnownDevices().first, isEmpty);
    expect(await db.watchFavorites().first, isEmpty);
  });
}
