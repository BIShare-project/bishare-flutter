import 'dart:io';
import 'dart:typed_data';

import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/clipboard/data/clipboard_history_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late ClipboardHistoryStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('bishare_clip_test');
    store = ClipboardHistoryStore(db, dir);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('ring buffer: trims to the newest 20 on insert', () async {
    for (var i = 1; i <= 25; i++) {
      await store.addText(text: 'item $i', senderAlias: 'Mac');
    }
    final rows = await store.watch().first;
    expect(rows.length, 20);
    // Newest first; the oldest five (1–5) were trimmed.
    expect(rows.first.textContent, 'item 25');
    expect(rows.last.textContent, 'item 6');
  });

  test('image entries persist bytes; trim/remove/clear unlink files',
      () async {
    final bytes = Uint8List.fromList(List.filled(64, 7));
    await store.addImage(bytes: bytes, mime: 'image/png', senderAlias: 'Mac');
    var rows = await store.watch().first;
    final entry = rows.single;
    expect(entry.kind, 'image');
    expect(entry.mime, 'image/png');
    final file = File(entry.filePath!);
    expect(file.existsSync(), true);
    expect(await file.readAsBytes(), bytes);

    // remove() deletes the row AND the file.
    await store.remove(entry);
    expect(await store.watch().first, isEmpty);
    expect(file.existsSync(), false);

    // Trimming an image entry out of the ring also unlinks its file.
    final small = ClipboardHistoryStore(db, dir, maxEntries: 2);
    await small.addImage(
        bytes: bytes, mime: 'image/png', senderAlias: 'Mac');
    final oldPath =
        (await small.watch().first).single.filePath!;
    await small.addText(text: 'a', senderAlias: 'Mac');
    await small.addText(text: 'b', senderAlias: 'Mac');
    rows = await small.watch().first;
    expect(rows.length, 2);
    expect(rows.every((r) => r.kind == 'text'), true);
    expect(File(oldPath).existsSync(), false);

    // clear() empties the table and the media dir.
    await small.addImage(
        bytes: bytes, mime: 'image/jpeg', senderAlias: 'Mac');
    final lastPath = (await small.watch().first).first.filePath!;
    await small.clear();
    expect(await small.watch().first, isEmpty);
    expect(File(lastPath).existsSync(), false);
  });
}
