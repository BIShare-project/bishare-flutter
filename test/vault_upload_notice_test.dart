import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/vault/data/vault_upload_notice.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Plugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _Uploader extends Mock implements VaultUploader {}

/// Drive uploads in the notification shade (owner 2026-10-21): the bar
/// while files go, then "Uploads finished" with how many.
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(const NotificationDetails());
    VaultUploadNotice.supportedForTest = true;
  });
  tearDownAll(() => VaultUploadNotice.supportedForTest = null);

  test('a bar while files go up, a summary when they are done', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    final plugin = _Plugin();
    when(
      () => plugin.show(
        id: any(named: 'id'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).thenAnswer((_) async {});
    when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});
    final uploader = _Uploader();
    when(() => uploader.progressOf(any())).thenReturn(null);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await db.vaultDao.enqueue(
      VaultTransfersCompanion.insert(
        direction: 'up',
        objectId: 'o1',
        name: 'IMG_1.jpg',
        localPath: '/x',
        size: 2000000,
        state: 'sending',
        createdAt: now,
        updatedAt: now,
      ),
    );
    when(
      () => uploader.progressOf(id),
    ).thenReturn((done: 500000, total: 2000000));
    final notice = VaultUploadNotice(
      dao: db.vaultDao,
      uploader: uploader,
      prefs: prefs,
      plugin: plugin,
    );
    await notice.start();
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    final shown = verify(
      () => plugin.show(
        id: 7701,
        title: 'Uploading to Drive',
        body: captureAny(named: 'body'),
        notificationDetails: captureAny(named: 'notificationDetails'),
      ),
    ).captured;
    // Sizes are bidi-isolated (decimalBytes); the words around them are not.
    expect(
      (shown.first as String).replaceAll(RegExp('[\u2068\u2069]'), ''),
      '500 KB of 2 MB',
    );
    final android = (shown[1] as NotificationDetails).android!;
    expect(android.progress, 250);
    expect(android.ongoing, isTrue);
    expect(android.subText, '1 left');

    await db.vaultDao.updateTransfer(
      id,
      VaultTransfersCompanion(
        state: const Value('done'),
        updatedAt: Value(now + 1),
      ),
    );
    when(() => uploader.progressOf(id)).thenReturn(null);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    verify(() => plugin.cancel(id: 7701)).called(greaterThanOrEqualTo(1));
    verify(
      () => plugin.show(
        id: 7702,
        title: 'Uploads finished',
        body: 'Uploaded: 1',
        notificationDetails: any(named: 'notificationDetails'),
      ),
    ).called(1);
    await notice.stop();
    await db.close();
  });
}
