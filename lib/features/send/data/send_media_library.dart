import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show MethodCall;
import 'package:photo_manager/photo_manager.dart';

import '../../../core/storage/all_files_access.dart';

/// Which part of the library a Send tab shows.
enum SendMediaKind { photo, video, audio }

/// What the app may read of the library.
enum SendMediaAccess { unknown, none, limited, full }

/// One album (photo_manager "path"), for the album sheet.
class SendAlbum {
  const SendAlbum({
    required this.id,
    required this.name,
    required this.count,
    this.cover,
    required this.path,
  });

  final String id;
  final String name;
  final int count;
  final AssetEntity? cover;
  final AssetPathEntity path;

  bool get isAll => path.isAll;
}

/// The device's library as the Send tab reads it (redesign-plan.md 3.1):
/// albums, newest-first pages by kind, small thumbnails through Flutter's own
/// image cache, and the change stream. Nothing here copies a file: originals
/// are exported only when sending ([original]).
///
/// Kept apart from Drive's backup library (`vault_photo_library.dart`) so the
/// tested backup code does not change with the redesign.
class SendMediaLibrary {
  /// Public so a test can stand in a fake; the app uses [instance].
  SendMediaLibrary();

  static final SendMediaLibrary instance = SendMediaLibrary();

  /// iOS and Android have a library; computers do not.
  static bool get available =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  static RequestType _type(SendMediaKind k) => switch (k) {
    SendMediaKind.photo => RequestType.image,
    SendMediaKind.video => RequestType.video,
    SendMediaKind.audio => RequestType.audio,
  };

  /// The access there is now; with [ask], the system prompt first. Never
  /// called at launch: only when a tab asks, or the user taps "Allow".
  Future<SendMediaAccess> access(SendMediaKind kind, {bool ask = false}) async {
    if (!available) return SendMediaAccess.none;
    // Android: the one "All files access" permission covers the library too
    // (AllFilesAccess). photo_manager checks only READ_MEDIA_*, so its own
    // check is skipped once all files are readable.
    if (AllFilesAccess.applies) {
      final all = ask
          ? await AllFilesAccess.request()
          : await AllFilesAccess.granted();
      if (all) {
        await PhotoManager.setIgnorePermissionCheck(true);
        return SendMediaAccess.full;
      }
      if (ask) return SendMediaAccess.none;
    }
    final option = PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: _type(kind),
        mediaLocation: false,
      ),
    );
    final state = ask
        ? await PhotoManager.requestPermissionExtend(requestOption: option)
        : await PhotoManager.getPermissionState(requestOption: option);
    return switch (state) {
      PermissionState.authorized => SendMediaAccess.full,
      PermissionState.limited => SendMediaAccess.limited,
      _ => SendMediaAccess.none,
    };
  }

  /// The albums holding [kind], the "all" album first.
  Future<List<SendAlbum>> albums(SendMediaKind kind) async {
    final paths = await PhotoManager.getAssetPathList(
      type: _type(kind),
      filterOption: _filter(kind),
    );
    final out = <SendAlbum>[];
    for (final p in paths) {
      final count = await p.assetCountAsync;
      if (count == 0) continue;
      final first = await p.getAssetListRange(start: 0, end: 1);
      out.add(
        SendAlbum(
          id: p.id,
          name: p.name,
          count: count,
          cover: first.isEmpty ? null : first.first,
          path: p,
        ),
      );
    }
    out.sort((a, b) => a.isAll == b.isAll ? 0 : (a.isAll ? -1 : 1));
    return out;
  }

  FilterOptionGroup _filter(SendMediaKind kind) => FilterOptionGroup(
    orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
  );

  /// [size] assets of [album] from [page] (0 is the newest).
  Future<List<AssetEntity>> page(SendAlbum album, int page, int size) =>
      album.path.getAssetListPaged(page: page, size: size);

  /// The original as a file, exported now (an iCloud photo downloads here).
  /// Null when it cannot be had.
  Future<File?> original(AssetEntity a) async {
    final f = await a.originFile;
    if (f == null || !await f.exists()) return null;
    return f;
  }

  /// The file name the library gives the asset.
  Future<String> name(AssetEntity a) async {
    final t = await a.titleAsync;
    return t.isEmpty ? '${a.id.hashCode.toUnsigned(32)}' : t;
  }

  /// The byte size where it is cheap to know (Android keeps the file on
  /// disk); null on iOS, where asking could download from iCloud.
  Future<int?> sizeOf(AssetEntity a) async {
    if (!Platform.isAndroid) return null;
    final f = await a.file;
    return f == null ? null : await f.length();
  }

  /// Something in the library changed.
  Stream<void> get changes {
    late final StreamController<void> c;
    void cb(MethodCall _) => c.add(null);
    c = StreamController<void>.broadcast(
      onListen: () {
        PhotoManager.addChangeCallback(cb);
        unawaited(PhotoManager.startChangeNotify());
      },
      onCancel: () {
        PhotoManager.removeChangeCallback(cb);
      },
    );
    return c.stream;
  }

  Future<void> openSettings() => PhotoManager.openSetting();

  /// iOS limited access: the system sheet to choose more photos.
  Future<void> chooseMore() => PhotoManager.presentLimited();
}

/// A square thumbnail of an asset through Flutter's image cache: the cache
/// is the LRU (redesign-plan.md "Performance budget" rule 2), keyed by asset
/// id and pixel size, so scrolling back never asks the library again.
@immutable
class AssetThumbProvider extends ImageProvider<AssetThumbProvider> {
  const AssetThumbProvider(this.asset, {this.px = 240});

  final AssetEntity asset;

  /// Thumbnail edge in physical pixels.
  final int px;

  @override
  Future<AssetThumbProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    AssetThumbProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load(key, decode));

  Future<ImageInfo> _load(
    AssetThumbProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await key.asset.thumbnailDataWithSize(
      ThumbnailSize.square(key.px),
      quality: 82,
    );
    if (bytes == null || bytes.isEmpty) {
      throw StateError('no thumbnail for ${key.asset.id}');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is AssetThumbProvider &&
      other.asset.id == asset.id &&
      other.px == px;

  @override
  int get hashCode => Object.hash(asset.id, px);
}
