import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/storage/vault_tables.dart';
import 'package:bishare/features/vault/data/vault_files.dart';
import 'package:bishare/features/vault/data/vault_keys.dart';
import 'package:bishare/features/vault/data/vault_meta.dart';
import 'package:bishare/features/vault/data/vault_photo_backup.dart';
import 'package:bishare/features/vault/data/vault_photo_library.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Uploader extends Mock implements VaultUploader {}

class _Files extends Mock implements VaultFiles {}

class _Keys extends Mock implements VaultKeyStore {}

/// A camera roll of files in a temporary folder, newest first.
class _Library implements PhotoLibrary {
  _Library(this.files);

  final List<File> files;
  PhotoAccess granted = PhotoAccess.full;
  PhotoAccess? onAsk;
  final StreamController<void> changed = StreamController<void>.broadcast();

  List<PhotoAsset> get assets => [
    for (var i = 0; i < files.length; i++)
      PhotoAsset(id: 'a$i', video: false, taken: DateTime(2026, 10, 1, 12, i)),
  ];

  @override
  bool get available => true;
  @override
  Future<PhotoAccess> access({bool ask = false}) async {
    if (ask && onAsk != null) granted = onAsk!;
    return granted;
  }

  @override
  Future<int> count() async => files.length;
  @override
  Future<List<PhotoAsset>> page(int page, int size) async =>
      assets.skip(page * size).take(size).toList();
  @override
  Future<({File file, String name})?> original(PhotoAsset asset) async {
    final f = files[int.parse(asset.id.substring(1))];
    return (file: f, name: f.uri.pathSegments.last);
  }

  @override
  Future<Uint8List?> thumbnail(PhotoAsset asset, int size) async => null;
  @override
  Stream<void> get changes => changed.stream;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> chooseMore() async {}
}

/// Photo backup (drive-plan.md tasks 5.2, 5.3, 5.8) against a real index
/// and a fake library: what is already in the Drive is only marked, the rest
/// is queued once into one folder, "Wi-Fi only" holds the queue on mobile
/// data except for "Back up now", and the badges follow the index.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(File('x'));
  });

  late Directory tmp;
  late AppDatabase db;
  late VaultDao dao;
  late _Uploader uploader;
  late _Files files;
  late _Keys keys;
  late SharedPreferences prefs;
  late bool wifi;
  late StreamController<void> network;
  final backups = <VaultPhotoBackup>[];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('photo-backup');
    db = AppDatabase(NativeDatabase.memory());
    dao = db.vaultDao;
    uploader = _Uploader();
    files = _Files();
    keys = _Keys();
    wifi = true;
    network = StreamController<void>.broadcast();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    when(() => keys.vaultKey()).thenAnswer((_) async => Uint8List(32));
    when(
      () => files.mkdir(any(), parent: any(named: 'parent')),
    ).thenAnswer((_) async => 'camera-folder');
    when(uploader.run).thenAnswer((_) async {});
    // The queue as the real uploader writes it, without the upload.
    when(
      () => uploader.enqueueAsset(
        any(),
        assetId: any(named: 'assetId'),
        name: any(named: 'name'),
        parent: any(named: 'parent'),
      ),
    ).thenAnswer((i) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      return dao.enqueue(
        VaultTransfersCompanion.insert(
          direction: 'up',
          objectId: 'o-${i.namedArguments[#assetId]}',
          parent: Value(i.namedArguments[#parent] as String?),
          name: i.namedArguments[#name] as String,
          localPath: (i.positionalArguments.first as File).path,
          size: 1,
          state: 'queued',
          createdAt: now,
          updatedAt: now,
          assetId: Value(i.namedArguments[#assetId] as String),
        ),
      );
    });
  });

  tearDown(() async {
    for (final b in backups) {
      await b.stop();
    }
    backups.clear();
    await network.close();
    await db.close();
    await tmp.delete(recursive: true);
  });

  File photo(String name, String content) =>
      File('${tmp.path}/$name')..writeAsStringSync(content);

  Future<void> driveHas(String id, String content, {int? trashedAt}) => db
      .into(db.vaultObjects)
      .insert(
        VaultObjectsCompanion.insert(
          id: id,
          name: '$id.jpg',
          kind: 'file',
          mtime: 1,
          hash: Value(
            VaultMetaCodec.b64u(
              Uint8List.fromList(sha256.convert(content.codeUnits).bytes),
            ),
          ),
          seq: 1,
          createdAt: 1,
          trashedAt: Value(trashedAt),
          encMeta: '',
        ),
      );

  VaultPhotoBackup make(
    _Library library, {
    int batch = 30,
    Future<void> Function()? catchUp,
  }) {
    final b = VaultPhotoBackup(
      library: library,
      dao: dao,
      uploader: uploader,
      files: files,
      keys: keys,
      prefs: prefs,
      folderName: () => 'Camera',
      onWifi: () async => wifi,
      networkChanges: network.stream,
      batch: batch,
      catchUp: catchUp,
    );
    backups.add(b);
    return b;
  }

  Future<Future<bool> Function(VaultTransfer)> gateOf() async {
    final captured = verify(() => uploader.mayStart = captureAny()).captured;
    return captured.last as Future<bool> Function(VaultTransfer);
  }

  test('what is in the Drive is marked; the rest is queued once into one '
      'folder', () async {
    final library = _Library([
      photo('a.jpg', 'first'),
      photo('b.jpg', 'second'),
    ]);
    await driveHas('x', 'first');
    await prefs.setBool('vault.photoBackup', true);
    final b = make(library);
    await b.start();
    await b.scan();

    expect(await dao.backedUpAssetIds(), {'a0'});
    verify(
      () => uploader.enqueueAsset(
        any(),
        assetId: 'a1',
        name: 'b.jpg',
        parent: 'camera-folder',
      ),
    ).called(1);
    verifyNever(
      () => uploader.enqueueAsset(
        any(),
        assetId: 'a0',
        name: any(named: 'name'),
        parent: any(named: 'parent'),
      ),
    );
    expect(b.left, 1, reason: 'the queued one is not in the Drive yet');
    expect(b.total, 2);

    // Another look while it is in the queue queues nothing new.
    await b.scan();
    expect((await dao.pendingTransfers()).length, 1);
    verify(() => files.mkdir('Camera')).called(1);
  });

  test('switched off: counted, nothing queued; switching on asks for the '
      'library and starts', () async {
    final library = _Library([photo('a.jpg', 'one')])
      ..granted = PhotoAccess.none
      ..onAsk = PhotoAccess.limited;
    final b = make(library);
    await b.start();
    await b.scan();
    expect(b.access, PhotoAccess.none);
    expect(await dao.pendingTransfers(), isEmpty);

    expect(await b.setOn(true), isTrue);
    expect(b.access, PhotoAccess.limited);
    expect(b.on, isTrue);
    await b.scan();
    expect((await dao.pendingTransfers()).single.assetId, 'a0');
  });

  test('refused: the switch stays off', () async {
    final library = _Library([photo('a.jpg', 'one')])
      ..granted = PhotoAccess.none
      ..onAsk = PhotoAccess.none;
    final b = make(library);
    expect(await b.setOn(true), isFalse);
    expect(b.on, isFalse);
  });

  test('"Wi-Fi only" holds backup uploads on mobile data; "Back up now" and '
      'other uploads go', () async {
    final library = _Library([photo('a.jpg', 'one'), photo('b.jpg', 'two')]);
    await prefs.setBool('vault.photoBackup', true);
    wifi = false;
    final b = make(library);
    await b.start();
    await b.scan();
    final gate = await gateOf();
    final queued = await dao.pendingTransfers();
    expect(queued.map((t) => t.assetId), ['a0', 'a1']);
    expect(await gate(queued[0]), isFalse);

    // Chosen with "Back up now": let through, and not queued a second time.
    await b.backUp([library.assets[0]]);
    expect(await gate(queued[0]), isTrue);
    expect(await gate(queued[1]), isFalse);
    expect((await dao.pendingTransfers()).length, 2);

    // A file the person uploads themselves is not photo backup's to hold.
    final now = DateTime.now().millisecondsSinceEpoch;
    await dao.enqueue(
      VaultTransfersCompanion.insert(
        direction: 'up',
        objectId: 'o-doc',
        name: 'doc.pdf',
        localPath: '/x',
        size: 1,
        state: 'queued',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final doc = (await dao.pendingTransfers()).firstWhere(
      (t) => t.assetId == null,
    );
    expect(await gate(doc), isTrue);

    await b.setWifiOnly(false);
    expect(await gate(queued[1]), isTrue);
  });

  test('a photo deleted from the Drive, or in its trash, is not backed up '
      'any more', () async {
    await driveHas('x', 'one', trashedAt: 5);
    await driveHas('y', 'two');
    await dao.markAssetBackedUp(
      'a0',
      VaultMetaCodec.b64u(
        Uint8List.fromList(sha256.convert('one'.codeUnits).bytes),
      ),
      'x',
    );
    await dao.markAssetBackedUp(
      'a1',
      VaultMetaCodec.b64u(
        Uint8List.fromList(sha256.convert('two'.codeUnits).bytes),
      ),
      'y',
    );
    expect(await dao.backedUpAssetIds(), {'a1'});
    expect(await dao.watchBackedUpAssets().first, {
      'a1': VaultMetaCodec.b64u(
        Uint8List.fromList(sha256.convert('two'.codeUnits).bytes),
      ),
    }, reason: 'the gallery hides the Drive copy of a photo on this phone');
  });

  test('a failed backup upload is tried again from a fresh copy', () async {
    final library = _Library([photo('a.jpg', 'one')]);
    await prefs.setBool('vault.photoBackup', true);
    final b = make(library);
    await b.start();
    await b.scan();
    final first = (await dao.pendingTransfers()).single;
    await dao.updateTransfer(
      first.id,
      const VaultTransfersCompanion(state: Value('failed')),
    );
    await b.scan();
    final now = await dao.watchTransfers().first;
    expect(now.length, 1);
    expect(now.single.id, isNot(first.id));
    expect(now.single.state, 'queued');
  });

  test('a full Drive stops backup after one more try, until switched on '
      'again', () async {
    final library = _Library([photo('a.jpg', 'one')]);
    await prefs.setBool('vault.photoBackup', true);
    final b = make(library);
    await b.start();
    await b.scan();
    Future<void> refuse() async {
      final t = (await dao.pendingTransfers()).single;
      await dao.updateTransfer(
        t.id,
        const VaultTransfersCompanion(
          state: Value('failed'),
          error: Value('STORAGE_LIMIT_EXCEEDED'),
        ),
      );
    }

    await refuse();
    await b.scan();
    expect(b.noRoom, isTrue);
    expect((await dao.pendingTransfers()).length, 1, reason: 'one more try');
    await refuse();
    await b.scan();
    expect(
      await dao.pendingTransfers(),
      isEmpty,
      reason: 'no photo after photo into a full Drive',
    );
    expect(await b.setOn(true), isTrue);
    expect(b.noRoom, isFalse);
    await b.scan();
    expect((await dao.pendingTransfers()).length, 1);
  });

  test('an upload that finished before the index caught up is not sent '
      'again', () async {
    final library = _Library([photo('a.jpg', 'one')]);
    await prefs.setBool('vault.photoBackup', true);
    var caughtUp = 0;
    final b = make(
      library,
      catchUp: () async {
        caughtUp++;
        await driveHas('x', 'one');
      },
    );
    await b.start();
    await b.scan();
    // The uploader finished and marked it; the index has not pulled yet.
    final t = (await dao.pendingTransfers()).single;
    await dao.updateTransfer(
      t.id,
      const VaultTransfersCompanion(state: Value('done')),
    );
    await dao.markAssetBackedUp(
      'a0',
      VaultMetaCodec.b64u(
        Uint8List.fromList(sha256.convert('one'.codeUnits).bytes),
      ),
      'x',
    );
    await b.scan();
    expect(caughtUp, 1);
    expect(await dao.pendingTransfers(), isEmpty);
    verify(
      () => uploader.enqueueAsset(
        any(),
        assetId: 'a0',
        name: any(named: 'name'),
        parent: any(named: 'parent'),
      ),
    ).called(1);
    expect(b.left, 0);
  });

  test('a reinstall puts photos in the Camera folder already there, and '
      'makes none while nothing is sent', () async {
    final library = _Library([photo('a.jpg', 'one'), photo('b.jpg', 'two')]);
    await driveHas('x', 'one');
    await prefs.setBool('vault.photoBackup', true);
    // Only photos already in the Drive: no folder at all.
    final first = make(_Library([library.files[0]]));
    await first.start();
    await first.scan();
    verifyNever(() => files.mkdir(any(), parent: any(named: 'parent')));
    await first.stop();

    await db
        .into(db.vaultObjects)
        .insert(
          VaultObjectsCompanion.insert(
            id: 'camera',
            name: 'Camera',
            kind: 'dir',
            mtime: 1,
            seq: 2,
            createdAt: 1,
            encMeta: '',
          ),
        );
    final b = make(library);
    await b.start();
    await b.scan();
    verifyNever(() => files.mkdir(any(), parent: any(named: 'parent')));
    expect((await dao.pendingTransfers()).single.parent, 'camera');
  });

  test('the badge of each photo', () {
    const backed = {'a'};
    const uploads = {
      'b': 'queued',
      'c': 'sending',
      'd': 'failed',
      'e': 'cancelled',
      'f': 'done',
    };
    PhotoBackupState s(String id) =>
        VaultPhotoBackup.stateOf(id, backed, uploads);
    expect(s('a'), PhotoBackupState.backedUp);
    expect(s('b'), PhotoBackupState.waiting);
    expect(s('c'), PhotoBackupState.uploading);
    expect(s('d'), PhotoBackupState.failed);
    expect(s('e'), PhotoBackupState.notBackedUp);
    expect(s('f'), PhotoBackupState.notBackedUp);
    expect(s('z'), PhotoBackupState.notBackedUp);
  });
}
