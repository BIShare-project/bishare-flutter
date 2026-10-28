// redesign 5.1: received files group by sender and sitting.
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/features/inbox/domain/inbox_groups.dart';
import 'package:flutter_test/flutter_test.dart';

var _id = 0;
TransferRecord _r(String alias, DateTime at, {String type = 'image/jpeg'}) =>
    TransferRecord(
      id: ++_id,
      fileName: 'f$_id',
      fileSize: 10,
      fileType: type,
      direction: 'received',
      deviceAlias: alias,
      deviceFingerprint: 'fp-$alias',
      encrypted: true,
      verified: true,
      timestamp: at,
    );

void main() {
  final t0 = DateTime(2026, 10, 28, 9);

  test('one sender in one sitting is one group, newest first', () {
    final g = groupReceived([
      _r('Mac', t0),
      _r('Mac', t0.add(const Duration(minutes: 1))),
      _r('Mac', t0.add(const Duration(minutes: 2)), type: 'application/pdf'),
    ]);
    expect(g, hasLength(1));
    expect(
      g.single.records.first.timestamp,
      t0.add(const Duration(minutes: 2)),
    );
    expect(g.single.media, hasLength(2));
    expect(g.single.files, hasLength(1));
    expect(g.single.bytes, 30);
  });

  test('a pause or another sender starts a new group', () {
    final g = groupReceived([
      _r('Mac', t0),
      _r('Mac', t0.add(const Duration(minutes: 30))),
      _r('Pixel', t0.add(const Duration(minutes: 31))),
      _r('Mac', t0.add(const Duration(minutes: 32))),
    ]);
    expect(g.map((x) => x.alias), ['Mac', 'Pixel', 'Mac', 'Mac']);
  });

  test('lists show the name the sender gave, only for this sender', () {
    TransferRecord named(String file, String alias) => TransferRecord(
      id: ++_id,
      fileName: file,
      fileSize: 1,
      direction: 'received',
      deviceAlias: alias,
      encrypted: false,
      verified: true,
      timestamp: t0,
    );
    expect(
      shownName(named('2026-10-28_MacBook-Pro_IMG_7130.jpg', 'MacBook Pro')),
      'IMG_7130.jpg',
    );
    expect(
      shownName(named('2026-10-28_Pixel_Notes (1).pdf', 'Pixel')),
      'Notes (1).pdf',
    );
    // Another sender's prefix, or none at all: the whole name.
    expect(
      shownName(named('2026-10-28_Galaxy_a.jpg', 'Pixel')),
      '2026-10-28_Galaxy_a.jpg',
    );
    expect(shownName(named('report.pdf', 'Pixel')), 'report.pdf');
  });

  test('videos count as media, other files as rows', () {
    final g = groupReceived([
      _r('Mac', t0, type: 'video/mp4'),
      _r('Mac', t0, type: 'audio/mpeg'),
    ]).single;
    expect(g.media.single.fileType, 'video/mp4');
    expect(g.files.single.fileType, 'audio/mpeg');
  });
}
