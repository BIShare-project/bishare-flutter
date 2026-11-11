import 'dart:io';

import 'package:bishare/features/send/presentation/tray_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bishare-live-');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<TrayCubit> tray(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    return TrayCubit(await SharedPreferences.getInstance());
  }

  test('a Live Photo is staged as photo + motion under one name', () async {
    // What photo_manager exports: the original and the paired video, each
    // under an export name.
    final photo = File('${dir.path}/ABC_123_o_IMG_4821.HEIC')
      ..writeAsBytesSync([1, 2, 3]);
    final video = File('${dir.path}/FullSizeRender_pair.mov')
      ..writeAsBytesSync([4, 5, 6, 7]);
    final t = await tray({});
    expect(t.sendLivePhotos, isTrue, reason: 'on by default');

    final pair = await t.stageLivePhoto(
      photo.path,
      video.path,
      name: 'IMG_4821.HEIC',
    );
    expect(pair.map((f) => f.name), ['IMG_4821.HEIC', 'IMG_4821.MOV']);
    expect(pair[0].liveGroup, isNotNull);
    expect(pair[1].liveGroup, pair[0].liveGroup);
    expect(t.state.map((f) => f.liveGroup).toSet(), {pair[0].liveGroup});
    expect(pair[1].mimeType, 'video/quicktime');
  });

  test('Live Photos go as the photo only when turned off or not Original',
      () async {
    expect((await tray({'sendLivePhotos': false})).sendLivePhotos, isFalse);
    expect((await tray({'mediaQuality': 'medium'})).sendLivePhotos, isFalse);
  });
}
