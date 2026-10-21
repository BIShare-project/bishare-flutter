import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// How much of the photo library this app may read.
enum PhotoAccess {
  /// Not asked yet, or asked and refused (the system settings can change it).
  none,

  /// iOS "Selected photos": only what the person chose.
  limited,

  /// Every photo and video.
  full,
}

/// One photo or video of the device's library.
class PhotoAsset {
  const PhotoAsset({
    required this.id,
    required this.video,
    required this.taken,
    this.durationS = 0,
    this.handle,
  });

  /// The library's own id for it (stable across launches on one device).
  final String id;
  final bool video;
  final DateTime taken;
  final int durationS;

  /// The platform object behind it, kept so thumbnails need no lookup.
  final Object? handle;
}

/// The device's photo library as Drive's photo backup needs it (drive-plan.md
/// tasks 5.1, 5.2, 5.8): newest first, paged, with thumbnails and the
/// original file. An interface, so the backup can be tested without a phone.
abstract class PhotoLibrary {
  /// iOS and Android only: computers have no photo library to back up.
  bool get available;

  /// The access there is now; with [ask], the system's prompt first.
  Future<PhotoAccess> access({bool ask = false});

  Future<int> count();

  /// [size] assets from [page] (0 is the newest).
  Future<List<PhotoAsset>> page(int page, int size);

  /// The asset itself as a file, and the name the library gives it. Null when
  /// it cannot be had (gone, or still in iCloud with no network).
  Future<({File file, String name})?> original(PhotoAsset asset);

  /// A square thumbnail of about [size] pixels, JPEG.
  Future<Uint8List?> thumbnail(PhotoAsset asset, int size);

  /// Something in the library changed (a new photo, a deletion).
  Stream<void> get changes;

  /// The system settings, where full access is given.
  Future<void> openSettings();

  /// iOS limited access: the system sheet to choose more photos.
  Future<void> chooseMore();
}

/// [PhotoLibrary] over the photo_manager plugin.
class DevicePhotoLibrary implements PhotoLibrary {
  final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: _startNotify,
    onCancel: _stopNotify,
  );
  AssetPathEntity? _all;
  static DevicePhotoLibrary? _listening;

  @override
  bool get available => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<PhotoAccess> access({bool ask = false}) async {
    if (!available) return PhotoAccess.none;
    final PermissionState state;
    if (ask) {
      state = await PhotoManager.requestPermissionExtend();
    } else {
      state = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
    }
    return switch (state) {
      PermissionState.authorized => PhotoAccess.full,
      PermissionState.limited => PhotoAccess.limited,
      _ => PhotoAccess.none,
    };
  }

  Future<AssetPathEntity?> _path() async {
    final cached = _all;
    if (cached != null) return cached;
    final paths = await PhotoManager.getAssetPathList(onlyAll: true);
    return _all = paths.firstOrNull;
  }

  @override
  Future<int> count() async => await (await _path())?.assetCountAsync ?? 0;

  @override
  Future<List<PhotoAsset>> page(int page, int size) async {
    final path = await _path();
    if (path == null) return const [];
    final list = await path.getAssetListPaged(page: page, size: size);
    return [
      for (final a in list)
        if (a.type == AssetType.image || a.type == AssetType.video)
          PhotoAsset(
            id: a.id,
            video: a.type == AssetType.video,
            taken: a.createDateTime,
            durationS: a.duration,
            handle: a,
          ),
    ];
  }

  Future<AssetEntity?> _entity(PhotoAsset asset) async =>
      asset.handle is AssetEntity
      ? asset.handle! as AssetEntity
      : await AssetEntity.fromId(asset.id);

  @override
  Future<({File file, String name})?> original(PhotoAsset asset) async {
    final e = await _entity(asset);
    if (e == null) return null;
    final file = await e.originFile;
    if (file == null || !await file.exists()) return null;
    final title = await e.titleAsync;
    return (file: file, name: title.isEmpty ? file.uri.pathSegments.last : title);
  }

  @override
  Future<Uint8List?> thumbnail(PhotoAsset asset, int size) async {
    final e = await _entity(asset);
    return e?.thumbnailDataWithSize(ThumbnailSize.square(size), quality: 80);
  }

  @override
  Stream<void> get changes {
    _listening = this;
    return _changes.stream;
  }

  static void _startNotify() {
    PhotoManager.addChangeCallback(_onChange);
    unawaited(PhotoManager.startChangeNotify());
  }

  static void _stopNotify() {
    PhotoManager.removeChangeCallback(_onChange);
    unawaited(PhotoManager.stopChangeNotify());
  }

  static void _onChange(Object? _) {
    final me = _listening;
    if (me == null) return;
    me._all = null; // counts and pages change with the library
    me._changes.add(null);
  }

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<void> chooseMore() => PhotoManager.presentLimited();
}
