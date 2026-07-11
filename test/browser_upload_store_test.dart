import 'dart:convert';
import 'dart:io';

import 'package:bishare/core/server/browser_upload_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// The chunked resumable browser-upload contract (feature #11):
/// `X-Chunk-Offset` must equal the `.part` length on disk (else the handler
/// answers 409 with the expected offset), the `.part` length IS the resume
/// offset (no DB, restart-safe), and the per-upload cap rolls back cleanly.
void main() {
  late Directory dir;
  late BrowserUploadStore store;

  Stream<List<int>> body(String s) => Stream.value(utf8.encode(s));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bishare_upload_test');
    store = BrowserUploadStore(() => dir);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  const id = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

  test('sequential appends advance the offset', () async {
    final first = await store.append(id, 0, body('hello '));
    expect(first.status, BrowserAppendStatus.ok);
    expect(first.offset, 6);
    final second = await store.append(id, 6, body('world'));
    expect(second.status, BrowserAppendStatus.ok);
    expect(second.offset, 11);
    expect(store.partFile(id).readAsStringSync(), 'hello world');
  });

  test('offset mismatch is rejected with the expected offset (409 driver)',
      () async {
    await store.append(id, 0, body('hello'));
    // Too far back (a duplicate retry) and too far forward (a lost chunk)
    // both report the length actually on disk.
    final behind = await store.append(id, 3, body('xxx'));
    expect(behind.status, BrowserAppendStatus.mismatch);
    expect(behind.offset, 5);
    final ahead = await store.append(id, 9, body('xxx'));
    expect(ahead.status, BrowserAppendStatus.mismatch);
    expect(ahead.offset, 5);
    // Nothing was written by the rejected attempts.
    expect(store.partFile(id).readAsStringSync(), 'hello');
    // The aligned retry succeeds.
    final ok = await store.append(id, 5, body('!'));
    expect(ok.status, BrowserAppendStatus.ok);
    expect(ok.offset, 6);
  });

  test('offset survives a restart: a fresh store reads the .part length',
      () async {
    await store.append(id, 0, body('0123456789'));
    final restarted = BrowserUploadStore(() => dir);
    expect(restarted.offsetOf(id), 10);
    // Metadata is gone after a restart, but that is display-only.
    expect(restarted.metaOf(id), isNull);
  });

  test('cap exceeded mid-chunk truncates back to the last clean offset',
      () async {
    store.maxBytes = 8;
    final first = await store.append(id, 0, body('12345'));
    expect(first.status, BrowserAppendStatus.ok);
    final second = await store.append(id, 5, body('123456'));
    expect(second.status, BrowserAppendStatus.tooLarge);
    expect(second.offset, 5); // rolled back — resume offset still trustworthy
    expect(store.offsetOf(id), 5);
  });

  test('a body error rolls back to the pre-append length', () async {
    await store.append(id, 0, body('stable'));
    Stream<List<int>> broken() async* {
      yield utf8.encode('partial');
      throw const SocketException('client vanished');
    }

    final result = await store.append(id, 6, broken());
    expect(result.status, BrowserAppendStatus.failed);
    expect(result.offset, 6);
    expect(store.offsetOf(id), 6);
  });

  test('metadata merges across chunks', () {
    store.remember(id, fileName: 'a.bin');
    store.remember(id, declaredSize: 42, mime: 'application/x-bin');
    final meta = store.metaOf(id)!;
    expect(meta.fileName, 'a.bin');
    expect(meta.declaredSize, 42);
    expect(meta.mime, 'application/x-bin');
  });

  test('upload ids that could escape the staging name are rejected', () {
    expect(BrowserUploadStore.isValidId('3f2504e0-4f89-11d3-9a0c-0305e82c3301'),
        isTrue);
    expect(BrowserUploadStore.isValidId(''), isFalse);
    expect(BrowserUploadStore.isValidId('short'), isFalse);
    expect(BrowserUploadStore.isValidId('../../../evil'), isFalse);
    expect(BrowserUploadStore.isValidId('abcd/efgh-ijkl-mnop'), isFalse);
    expect(BrowserUploadStore.isValidId('a' * 65), isFalse);
  });

  test('discard removes the .part and metadata', () async {
    await store.append(id, 0, body('data'));
    store.remember(id, fileName: 'x');
    store.discard(id);
    expect(store.partFile(id).existsSync(), isFalse);
    expect(store.metaOf(id), isNull);
    expect(store.offsetOf(id), 0);
  });

  test('concurrent appends at the same offset are serialized — no corruption',
      () async {
    // Two chunks race at offset 0 (a browser retry firing before the original
    // returns). Without per-id serialization both pass the offset check and
    // interleave, doubling the length; serialized, exactly one wins and the
    // other sees the post-write length and 409s.
    final a = store.append(id, 0, body('AAAAA'));
    final b = store.append(id, 0, body('BBBBB'));
    final results = await Future.wait([a, b]);
    expect(results[0].status, BrowserAppendStatus.ok);
    expect(results[1].status, BrowserAppendStatus.mismatch);
    expect(results[1].offset, 5); // realign to what actually reached disk
    expect(store.partFile(id).readAsStringSync(), 'AAAAA');
  });

  test('an append queued at the next offset runs after the one in flight',
      () async {
    // Fired back-to-back without awaiting the first: the second must observe
    // the first chunk already durable (expected == 2) and append cleanly.
    final a = store.append(id, 0, body('AA'));
    final b = store.append(id, 2, body('BB'));
    final results = await Future.wait([a, b]);
    expect(results[0].status, BrowserAppendStatus.ok);
    expect(results[1].status, BrowserAppendStatus.ok);
    expect(store.partFile(id).readAsStringSync(), 'AABB');
  });

  test('a new upload is refused once staging is at the file cap', () async {
    store.maxStagingFiles = 2;
    const a = 'aaaaaaaa-1111-1111-1111-111111111111';
    const b = 'bbbbbbbb-2222-2222-2222-222222222222';
    const c = 'cccccccc-3333-3333-3333-333333333333';
    expect((await store.append(a, 0, body('x'))).status, BrowserAppendStatus.ok);
    expect((await store.append(b, 0, body('y'))).status, BrowserAppendStatus.ok);
    // A third BRAND-NEW upload is turned away — nothing is staged for it.
    final third = await store.append(c, 0, body('z'));
    expect(third.status, BrowserAppendStatus.capacity);
    expect(store.partFile(c).existsSync(), isFalse);
    // But an already-staged upload keeps appending past the cap.
    final more = await store.append(a, 1, body('X'));
    expect(more.status, BrowserAppendStatus.ok);
    expect(store.partFile(a).readAsStringSync(), 'xX');
  });

  test('a completed upload id replays the saved name within the grace window',
      () {
    expect(store.completedName(id), isNull);
    store.rememberCompleted(id, 'photo (1).jpg');
    expect(store.completedName(id), 'photo (1).jpg');
    // Past the 10-minute grace window it is forgotten, so a genuinely new
    // upload that happens to reuse the id is not shadowed by the old result.
    final later = DateTime.now().add(
      BrowserUploadStore.completedGrace + const Duration(minutes: 1),
    );
    expect(store.completedName(id, now: later), isNull);
    expect(store.completedName(id), isNull);
  });
}
