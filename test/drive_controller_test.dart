import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/vault/data/vault_files.dart';
import 'package:bishare/features/vault/presentation/drive/drive_controller.dart';
import 'package:bishare/features/vault/presentation/drive/drive_format.dart';
import 'package:bishare/features/vault/presentation/drive/drive_page.dart' show storageByKind;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Drive file manager's state (drive-plan.md task 4.7): what each view
/// shows, in which order, how selection and "back" behave, and the names
/// given to copies.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    var seq = 0;
    Future<void> add(
      String id,
      String name,
      String kind, {
      String? parent,
      int size = 0,
      String? mime,
      int mtime = 0,
      int created = 0,
      int? trashed,
      String? blob,
    }) => db.vaultDao.upsertObjects([
      VaultObjectsCompanion.insert(
        id: id,
        parent: Value(parent),
        name: name,
        kind: kind,
        size: Value(kind == 'file' ? size : null),
        blobSize: Value(kind == 'file' ? size : null),
        blobId: Value(kind == 'file' ? (blob ?? 'b-$id') : null),
        mime: Value(mime),
        mtime: mtime,
        seq: ++seq,
        createdAt: created,
        trashedAt: Value(trashed),
        encMeta: 'x',
      ),
    ]);
    await add('d1', 'photos', 'dir', mtime: 5);
    await add('d2', 'Archive', 'dir', mtime: 1);
    await add('f1', 'b.txt', 'file', size: 30, mime: 'text/plain', mtime: 3, created: 100);
    await add('f2', 'A.jpg', 'file', size: 10, mime: 'image/jpeg', mtime: 9, created: 300);
    await add('f3', 'c.mp3', 'file', size: 20, mime: 'audio/mpeg', mtime: 1, created: 200);
    await add('f4', 'inside.pdf', 'file', parent: 'd1', size: 5, mime: 'application/pdf', created: 400);
    await add('f5', 'same.jpg', 'file', parent: 'd1', size: 10, mime: 'image/jpeg', blob: 'b-f2');
    await add('t1', 'gone', 'dir', trashed: 1000);
    await add('t2', 'in gone.txt', 'file', parent: 't1', size: 7, mime: 'text/plain', trashed: 1000);
    await add('t3', 'loose.txt', 'file', size: 9, mime: 'text/plain', trashed: 2000, blob: 'b-t3');
  });
  tearDown(() => db.close());

  Future<List<String>> names(DriveController c) async =>
      (await c.items().first).map((o) => o.name).toList();

  test('folders first, then by name without case; the other sorts flip on a second tap', () async {
    final c = DriveController(db.vaultDao);
    expect(await names(c), ['Archive', 'photos', 'A.jpg', 'b.txt', 'c.mp3']);
    c.setSort(DriveSort.size); // largest first
    expect(await names(c), ['Archive', 'photos', 'b.txt', 'c.mp3', 'A.jpg']);
    c.setSort(DriveSort.size); // smallest first
    expect(await names(c), ['Archive', 'photos', 'A.jpg', 'c.mp3', 'b.txt']);
    c.setSort(DriveSort.modified); // newest first
    expect(await names(c), ['photos', 'Archive', 'A.jpg', 'b.txt', 'c.mp3']);
    c.setSort(DriveSort.kind);
    expect(await names(c), ['Archive', 'photos', 'A.jpg', 'c.mp3', 'b.txt']);
  });

  test('sort and layout are remembered on the device', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    DriveController(db.vaultDao, prefs: prefs)
      ..setSort(DriveSort.size)
      ..setGrid(true);
    final again = DriveController(db.vaultDao, prefs: prefs);
    expect(again.sort, DriveSort.size);
    expect(again.ascending, isFalse);
    expect(again.grid, isTrue);
  });

  test('views across the Drive: recent, photos and videos, documents, audio, trash', () async {
    final c = DriveController(db.vaultDao)..setView(DriveView.recent);
    final recent = await names(c);
    expect(recent.first, 'inside.pdf', reason: 'newest first');
    expect(recent, isNot(contains('loose.txt')), reason: 'nothing from the trash');
    c.setView(DriveView.media);
    expect(await names(c), ['A.jpg', 'same.jpg']);
    c.setView(DriveView.documents);
    expect(await names(c), ['b.txt', 'inside.pdf']);
    c.setView(DriveView.audio);
    expect(await names(c), ['c.mp3']);
    c.setView(DriveView.trash);
    expect(await names(c), ['gone', 'loose.txt'], reason: 'a trashed folder shows once, not its contents');
  });

  test('search: any case, the whole Drive, never the trash, % and _ are plain text', () async {
    final c = DriveController(db.vaultDao)..setQuery('JPG');
    expect(await names(c), ['A.jpg', 'same.jpg']);
    c.setQuery('txt');
    expect(await names(c), ['b.txt']);
    c.setQuery('%');
    expect(await names(c), isEmpty);
  });

  test('back: selection, then search, then folder, then view, then leave', () async {
    final c = DriveController(db.vaultDao);
    final photos = (await db.vaultDao.object('d1'))!;
    c.open(photos);
    expect(await names(c), ['inside.pdf', 'same.jpg']);
    c.toggle('f4');
    expect(c.up(), isTrue);
    expect(c.selecting, isFalse);
    expect(c.folder, 'd1');
    expect(c.up(), isTrue);
    expect(c.folder, isNull);
    c.setView(DriveView.audio);
    expect(c.up(), isTrue);
    expect(c.view, DriveView.files);
    expect(c.up(), isFalse, reason: 'at the top the screen may close');
  });

  test('reveal opens the folder of a search result with its whole path', () async {
    final c = DriveController(db.vaultDao)..setQuery('inside');
    await c.reveal('d1');
    expect(c.searching, isFalse);
    expect(c.path.map((o) => o.name), ['photos']);
  });

  test('selection: shift range and select all', () async {
    final c = DriveController(db.vaultDao);
    final visible = await c.items().first;
    c.toggle(visible[1].id);
    c.selectRange(visible, visible[3].id);
    expect(c.selected, {visible[1].id, visible[2].id, visible[3].id});
    c.selectAll(visible);
    expect(c.selected.length, visible.length);
    c.selectAll(visible);
    expect(c.selected, isEmpty, reason: 'a second "select all" clears');
  });

  test('copies and clashes get " (1)", " (2)", without case', () {
    expect(freeNameIn({'a.txt'}, 'A.TXT'), 'A (1).TXT');
    expect(freeNameIn({'a.txt', 'a (1).txt'}, 'a.txt'), 'a (2).txt');
    expect(freeNameIn({'photos'}, 'Photos'), 'Photos (1)');
    expect(freeNameIn({}, '.env'), '.env');
    expect(freeNameIn({'.env'}, '.env'), '.env (1)');
  });

  test('storage by kind counts each stored blob once; trash only what no live file uses', () async {
    final live = await db.vaultDao.watchLive().first;
    final trash = await db.vaultDao.watchTrash().first;
    final by = storageByKind(live, trash);
    expect(by['media'], 10, reason: 'A.jpg and same.jpg share one blob');
    expect(by['documents'], 35);
    expect(by['audio'], 20);
    expect(by['trash'], 16);
  });

  test('sizes the way the quota counts them', () {
    expect(decimalBytes(999), '999 B');
    expect(decimalBytes(5000000000), '5 GB');
    expect(decimalBytes(1834000000), '1.83 GB');
    expect(decimalBytes(2400000), '2.4 MB');
    expect(decimalBytes(12000000000), '12 GB');
  });
}
