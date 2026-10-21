import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:bishare/features/vault/data/vault_upload_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Uploader extends Mock implements VaultUploader {}

VaultTransfer _t(
  int id, {
  required String state,
  int size = 100,
  int created = 10,
  int updated = 10,
}) => VaultTransfer(
  id: id,
  direction: 'up',
  objectId: 'o$id',
  name: 'f$id.jpg',
  localPath: '/f$id',
  size: size,
  state: state,
  bytesDone: 0,
  createdAt: created,
  updatedAt: updated,
);

/// The upload bar (owner 2026-10-21: it went "naik turun tidak teratur"):
/// finished files stay in the go, the one being sent counts what went, and
/// files joining a go never pull the bar back.
void main() {
  late _Uploader uploader;
  setUp(() {
    uploader = _Uploader();
    when(() => uploader.progressOf(any())).thenReturn(null);
  });

  test('nothing going up: no batch', () {
    expect(UploadBatch.of(const [], uploader), isNull);
    expect(UploadBatch.of([_t(1, state: 'done')], uploader), isNull);
  });

  test('a finished file stays in the go and the file being sent counts', () {
    when(() => uploader.progressOf(2)).thenReturn((done: 50, total: 200));
    final batch = UploadBatch.of([
      _t(1, state: 'done', created: 10, updated: 20),
      _t(2, state: 'sending', created: 11),
      _t(3, state: 'queued', created: 12),
      // Finished before this go began: an earlier one.
      _t(4, state: 'done', created: 1, updated: 5),
    ], uploader)!;
    expect(batch.files, 3);
    expect(batch.filesDone, 1);
    expect(batch.bytes, 300);
    expect(batch.bytesDone, 125); // 100 + a quarter of 100
    expect(batch.current!.id, 2);
    expect(batch.fraction, closeTo(125 / 300, 1e-9));
  });

  test('the bar never goes back within a go; a new go starts over', () {
    final bar = OneWayProgress();
    final first = UploadBatch.of([
      _t(1, state: 'done', updated: 20),
      _t(2, state: 'queued'),
    ], uploader);
    expect(bar.of(first), 0.5);
    // Thirty more photos join the same go: the total grows.
    final more = UploadBatch.of([
      _t(1, state: 'done', updated: 20),
      _t(2, state: 'queued'),
      for (var i = 3; i < 33; i++) _t(i, state: 'queued', created: 15),
    ], uploader);
    expect(more!.fraction, lessThan(0.5));
    expect(bar.of(more), 0.5);
    expect(bar.of(null), isNull);
    final next = UploadBatch.of([
      _t(40, state: 'queued', created: 99),
    ], uploader);
    expect(bar.of(next), 0);
  });

  test('stopped uploads alone still show, without a bar', () {
    final batch = UploadBatch.of([_t(1, state: 'failed')], uploader)!;
    expect(batch.running, isEmpty);
    expect(batch.stopped, 1);
    expect(batch.fraction, isNull);
  });
}
