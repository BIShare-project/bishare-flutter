// Store screenshots, not goldens: renders the real BIShare screens on the
// host — no simulator, no emulator — at the sizes the stores ask for, to PNG
// files. Runs only when BISHARE_SHOTS_DIR is set; store/screens/shoot.sh runs
// it once per language and then frames the results:
//
//   BISHARE_SHOTS_DIR=/tmp/raw BISHARE_SHOTS_LOCALES=ja \
//     flutter test test/preview/store_screenshots_test.dart
//
// Optional: BISHARE_SHOTS_PRESETS=ios_phone,mac, BISHARE_SHOTS_ONLY=plans
// (screens whose file name contains one of the words), BISHARE_SHOTS_THEME=light
// (the stores get dark), and BISHARE_SHOTS_PLAN=drive_250gb_yearly (the plans
// page as a subscriber sees it; the stores get the free Drive). Output:
// `<dir>/<preset>/<lang>/<n>_<screen>.png`. The UI is the app's own widgets
// with fixed state (a cast of peers, a room, default settings), drawn the way
// the target platform draws it (debugDefaultTargetPlatformOverride). The
// status bar, the device and the captions are added by store/screens/frame.py.
//
// A phone draws Japanese, Arabic or Hindi in an IBM Plex Sans label with its
// system fonts; the test engine has none. For those languages the test loads
// IBM Plex Sans with the matching Noto glyphs merged in
// (store/screens/instance_fonts.py), so one process serves one such language.
//
// Drive (drive-plan.md task 4.11) is drawn too, into `<lang>/drive/`, which
// frame.py does not read, so every language is checked for overflows and
// missing keys. One Drive screen goes to the stores as `6_drive`: the photos
// and their backup on phones and tablets, the file manager on computers.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:photo_manager/photo_manager.dart';
import 'package:bishare/features/send/data/send_media_library.dart';
import 'package:bishare/features/history/presentation/history_cubit.dart';
import 'package:bishare/features/inbox/presentation/inbox_tab.dart';
import 'package:bishare/features/inbox/presentation/inbox_cubit.dart';
import 'package:bishare/core/desktop/desktop_service.dart';
import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/l10n/app_locales.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/storage/vault_tables.dart';
import 'package:bishare/core/theme/app_theme.dart';
import 'package:bishare/features/send/presentation/send_selection_cubit.dart';
import 'package:bishare/core/theme/app_tokens.dart';
import 'package:bishare/core/ui/app_bottom_nav.dart';
import 'package:bishare/core/ui/app_nav_rail.dart';
import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/core/ui/app_svg_icon.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:bishare/features/discovery/presentation/discovery_cubit.dart';
import 'package:bishare/features/favorites/presentation/favorites_cubit.dart';
import 'package:bishare/features/home/home_page.dart';
import 'package:bishare/features/receive/presentation/receive_cubit.dart';
import 'package:bishare/features/remote/presentation/remote_share_page.dart';
import 'package:bishare/features/room/domain/room_models.dart';
import 'package:bishare/features/room/presentation/room_cubit.dart';
import 'package:bishare/features/send/domain/sendable_file.dart';
import 'package:bishare/features/send/presentation/send_cubit.dart';
import 'package:bishare/features/send/presentation/tray_cubit.dart';
import 'package:bishare/features/settings/domain/settings.dart';
import 'package:bishare/features/settings/presentation/settings_cubit.dart';
import 'package:bishare/features/settings/presentation/settings_page.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
import 'package:bishare/features/vault/data/vault_purchases.dart';
import 'package:bishare/features/vault/presentation/drive/drive_plans_page.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:bishare/features/vault/data/vault_downloads.dart';
import 'package:bishare/features/vault/data/vault_key_copy.dart';
import 'package:bishare/features/vault/data/vault_sync.dart';
import 'package:bishare/features/vault/data/vault_photo_backup.dart';
import 'package:bishare/features/vault/data/vault_photo_library.dart';
import 'package:bishare/features/vault/data/vault_thumbs.dart';
import 'package:bishare/features/vault/data/vault_uploader.dart';
import 'package:bishare/features/vault/presentation/drive/drive_controller.dart';
import 'package:bishare/features/vault/presentation/drive/drive_page.dart';
import 'package:bishare/features/vault/presentation/drive/drive_widgets.dart';
import 'package:bishare/features/vault/presentation/vault_account_page.dart';
import 'package:bishare/features/vault/presentation/vault_desktop_pairing.dart';
import 'package:bishare/features/web_nearby/presentation/web_nearby_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One store device: logical size, pixel ratio, how it draws, its safe-area
/// insets (status bar, home indicator) and the name this device goes by.
typedef _Preset = ({
  Size size,
  double ratio,
  TargetPlatform platform,
  EdgeInsets insets,
  String self,
  String type,
});

const Map<String, _Preset> _presets = {
  // iPhone 17 Pro Max: 1320×2868
  'ios_phone': (
    size: Size(440, 956),
    ratio: 3,
    platform: TargetPlatform.iOS,
    insets: EdgeInsets.only(top: 62, bottom: 34),
    self: 'iPhone 17',
    type: 'mobile',
  ),
  // iPhone Duo outer display: 1398×2034 (Apple's screenshot
  // specifications; the logical size assumes 3x)
  'ios_duo_outer': (
    size: Size(466, 678),
    ratio: 3,
    platform: TargetPlatform.iOS,
    insets: EdgeInsets.only(top: 54, bottom: 30),
    self: 'iPhone 17',
    type: 'mobile',
  ),
  // iPhone Duo inner display: 2007×2853
  'ios_duo_inner': (
    size: Size(669, 951),
    ratio: 3,
    platform: TargetPlatform.iOS,
    insets: EdgeInsets.only(top: 32, bottom: 24),
    self: 'iPad Pro',
    type: 'mobile',
  ),
  // iPad Pro 13": 2064×2752
  'ios_ipad': (
    size: Size(1032, 1376),
    ratio: 2,
    platform: TargetPlatform.iOS,
    insets: EdgeInsets.only(top: 24, bottom: 20),
    self: 'iPad Pro',
    type: 'mobile',
  ),
  // A 6.3" Android phone at 3.5x: 1442×3122
  'android_phone': (
    size: Size(412, 892),
    ratio: 3.5,
    platform: TargetPlatform.android,
    insets: EdgeInsets.only(top: 40, bottom: 24),
    self: 'Pixel 9',
    type: 'mobile',
  ),
  // A 10" Android tablet: 1600×2560
  'android_tablet': (
    size: Size(800, 1280),
    ratio: 2,
    platform: TargetPlatform.android,
    insets: EdgeInsets.only(top: 28, bottom: 24),
    self: 'Galaxy Tab S10',
    type: 'mobile',
  ),
  // The macOS window (fixed 1000×680, see DesktopService) at 2x
  'mac': (
    size: Size(1000, 680),
    ratio: 2,
    platform: TargetPlatform.macOS,
    insets: EdgeInsets.zero,
    self: 'MacBook Pro',
    type: 'desktop',
  ),
};

/// Drawn only when named in BISHARE_SHOTS_PRESETS, to look at screens no
/// store gets: Windows (the Drive approved by a phone, no sign-in), and the
/// window at its real size for the Microsoft Store and Snap screenshots
/// (store/screenshots/compose.py).
const Map<String, _Preset> _reviewPresets = {
  'windows': (
    // Taller than the window, to see whole pages.
    size: Size(1000, 1500),
    ratio: 2,
    platform: TargetPlatform.windows,
    insets: EdgeInsets.zero,
    self: 'Windows PC',
    type: 'desktop',
  ),
  'windows_store': (
    // The window's fixed size (desktop_service.dart).
    size: Size(1000, 680),
    ratio: 2,
    platform: TargetPlatform.windows,
    insets: EdgeInsets.zero,
    self: 'Windows PC',
    type: 'desktop',
  ),
};

/// The Noto glyphs merged into IBM Plex Sans for each language Plex lacks.
const Map<String, String> _scriptFont = {
  'ar': 'NotoSansArabic',
  'hi': 'NotoSansDevanagari',
  'ja': 'NotoSansJP',
  'ko': 'NotoSansKR',
  'zh-Hans': 'NotoSansSC',
  'zh-Hant': 'NotoSansTC',
};

final String? _dir = Platform.environment['BISHARE_SHOTS_DIR'];
final ThemeMode _theme = Platform.environment['BISHARE_SHOTS_THEME'] == 'light'
    ? ThemeMode.light
    : ThemeMode.dark;
List<String> _list(String key) => (Platform.environment[key] ?? '')
    .split(',')
    .where((s) => s.isNotEmpty)
    .toList();

String _tag(Locale l) => l.countryCode == null
    ? l.languageCode
    : '${l.languageCode}-${l.countryCode}';

class _Discovery extends MockCubit<List<DiscoveredDevice>>
    implements DiscoveryCubit {}

class _Receive extends MockCubit<ReceiveState> implements ReceiveCubit {}

class _Send extends MockCubit<SendState> implements SendCubit {}

class _Tray extends MockCubit<List<SendableFile>> implements TrayCubit {}

class _Favorites extends MockCubit<Map<String, FavoriteDevice>>
    implements FavoritesCubit {}

class _Room extends MockCubit<RoomState> implements RoomCubit {}

class _Settings extends MockCubit<Settings> implements SettingsCubit {}

class _WebNearby extends MockCubit<WebNearbyState> implements WebNearbyCubit {}

class _Desktop extends Mock implements DesktopService {}

class _Inbox extends MockCubit<List<TransferRecord>> implements InboxCubit {}

class _History extends MockCubit<HistoryState> implements HistoryCubit {}

/// The sample photos (store/screens/photos, Unsplash License), read once.
final Map<String, Uint8List> _photoBytes = {};

List<String> get _photoNames => _photoBytes.keys.toList()..sort();

Future<void> _loadPhotos() async {
  if (_photoBytes.isNotEmpty) return;
  final dir = Directory('store/screens/photos');
  for (final f in dir.listSync().whereType<File>()) {
    if (f.path.endsWith('.jpg')) {
      _photoBytes[f.uri.pathSegments.last] = await f.readAsBytes();
    }
  }
}

/// A phone library of the sample photos, newest first, for the Send tab.
class _FakeLibrary extends SendMediaLibrary {
  _FakeLibrary() {
    final now = DateTime(2026, 10, 28, 18).millisecondsSinceEpoch ~/ 1000;
    _assets = [
      for (final (i, name) in _photoNames.indexed)
        AssetEntity(
          id: name,
          typeInt: 1,
          width: 1200,
          height: 1200,
          title: name,
          createDateSecond: now - i * 5400,
        ),
    ];
  }

  late final List<AssetEntity> _assets;

  List<AssetEntity> get assets => _assets;

  @override
  Future<SendMediaAccess> access(
    SendMediaKind kind, {
    bool ask = false,
  }) async => SendMediaAccess.full;

  @override
  Future<List<SendAlbum>> albums(SendMediaKind kind) async => [
    if (kind == SendMediaKind.photo)
      SendAlbum(
        id: 'all',
        name: 'Recents',
        count: _assets.length,
        cover: _assets.first,
        path: AssetPathEntity(id: 'all', name: 'Recents', isAll: true),
      ),
  ];

  @override
  Future<List<AssetEntity>> page(SendAlbum album, int page, int size) async =>
      page == 0 ? _assets.take(size).toList() : const [];

  @override
  Future<Uint8List?> thumbnail(AssetEntity a, int px) async =>
      _photoBytes[a.id];

  @override
  Future<String> name(AssetEntity a) async => a.id;

  @override
  // A phone photo's size, not the small sample's.
  Future<int?> sizeOf(AssetEntity a) async =>
      3400000 + (_photoBytes[a.id]?.length ?? 0) * 3;

  @override
  Stream<void> get changes => const Stream.empty();
}

/// Photos received today and yesterday from the other devices.
List<TransferRecord> _received() {
  final now = DateTime(2026, 10, 28, 18, 20);
  final from = ['Leo', 'Nadia', 'Leo', 'Studio'];
  return [
    for (final (i, name) in _photoNames.indexed)
      TransferRecord(
        id: i + 1,
        fileName: 'IMG_${2041 + i}.jpg',
        savedPath: File('store/screens/photos/$name').absolute.path,
        fileSize: 3200000 + i * 410000,
        fileType: 'image/jpeg',
        direction: 'received',
        deviceAlias: from[(i ~/ 4) % from.length],
        deviceFingerprint: 'fp-${from[(i ~/ 4) % from.length].toLowerCase()}',
        encrypted: true,
        verified: true,
        timestamp: now.subtract(
          Duration(minutes: i < 8 ? i * 3 : 1440 + i * 7),
        ),
      ),
  ];
}

/// Launch at login, off (Settings on a computer).
DesktopService _desktop() {
  final d = _Desktop();
  when(d.isAutostartEnabled).thenAnswer((_) async => false);
  return d;
}

class _Account extends Mock implements VaultAccount {}

class _Purchases extends Mock implements VaultPurchases {}

class _KeyCopy extends Mock implements VaultKeyCopy {}

class _Sync extends Mock implements VaultSync {}

class _Uploader extends Mock implements VaultUploader {}

class _Downloads extends Mock implements VaultDownloads {}

class _Thumbs extends Mock implements VaultThumbs {}

class _Backup extends Mock implements VaultPhotoBackup {}

/// A phone's camera roll: 30 photos and videos, newest first.
class _Library implements PhotoLibrary {
  @override
  Future<void> clearExports() async {}

  static final _assets = [
    for (var i = 0; i < 30; i++)
      PhotoAsset(
        id: 'a$i',
        video: i % 7 == 3,
        taken: DateTime(2026, 10, 20).subtract(Duration(hours: 5 * i)),
        durationS: i % 7 == 3 ? 14 + 9 * i : 0,
      ),
  ];

  @override
  bool get available => true;
  @override
  Future<PhotoAccess> access({bool ask = false}) async => PhotoAccess.full;
  @override
  Future<int> count() async => _assets.length;
  @override
  Future<List<PhotoAsset>> page(int page, int size) async =>
      _assets.skip(page * size).take(size).toList();
  @override
  Future<({File file, String name})?> original(PhotoAsset asset) async => null;
  @override
  Future<Uint8List?> thumbnail(PhotoAsset asset, int size) async =>
      _thumb(int.parse(asset.id.substring(1)));
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> chooseMore() async {}
}

class _Db extends Mock implements AppDatabase {}

/// The index as plain lists: a drift stream inside a widget test never settles.
class _Dao extends Mock implements VaultDao {}

/// A Drive with some of everything: three folders and a mix of files at the
/// top, photos and videos inside "Bali 2026".
List<VaultObject> _driveObjects() {
  final now = DateTime.now().millisecondsSinceEpoch;
  var seq = 0;
  VaultObject o(
    String id,
    String name, {
    String? parent,
    String? mime,
    int size = 0,
    int ago = 0,
  }) {
    final at = now - ago * 3600000;
    return VaultObject(
      id: id,
      parent: parent,
      name: name,
      kind: mime == null ? 'dir' : 'file',
      size: mime == null ? null : size,
      mtime: at,
      mime: mime,
      blobId: mime == null ? null : 'b-$id',
      blobSize: mime == null ? null : size,
      hasThumb:
          mime != null &&
          (mime.startsWith('image/') || mime.startsWith('video/')),
      seq: ++seq,
      createdAt: at,
      encMeta: 'x',
    );
  }

  const mb = 1000000;
  return [
    o('bali', 'Bali 2026', ago: 30),
    o('projects', 'Projects', ago: 50),
    o('scans', 'Scans', ago: 200),
    o('f1', 'IMG_2041.jpg', mime: 'image/jpeg', size: 4718592, ago: 2),
    o('f2', 'Slides_Q4.pdf', mime: 'application/pdf', size: 12582912, ago: 5),
    o('f3', 'VID_0412.mp4', mime: 'video/mp4', size: 268435456, ago: 9),
    o(
      'f4',
      'Contract_2026.docx',
      mime:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      size: 184320,
      ago: 26,
    ),
    o('f5', 'Podcast_ep12.mp3', mime: 'audio/mpeg', size: 38 * mb, ago: 70),
    o(
      'f6',
      'Budget.xlsx',
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      size: 96256,
      ago: 120,
    ),
    for (var i = 0; i < 14; i++)
      o(
        'p$i',
        i % 5 == 3 ? 'VID_${2101 + i}.mp4' : 'IMG_${2101 + i}.jpg',
        parent: 'bali',
        mime: i % 5 == 3 ? 'video/mp4' : 'image/jpeg',
        size: i % 5 == 3 ? 180 * mb : 3 * mb + i * 211000,
        ago: 30 + i,
      ),
    o(
      's1',
      'Passport.pdf',
      parent: 'scans',
      mime: 'application/pdf',
      size: 2 * mb,
      ago: 210,
    ),
    o(
      'w1',
      'Roadmap.pdf',
      parent: 'projects',
      mime: 'application/pdf',
      size: 5 * mb,
      ago: 60,
    ),
  ];
}

/// Thumbnails: a soft two-colour gradient with a sun, one palette per photo.
Uint8List _thumb(int seed) {
  if (_photoBytes.isNotEmpty) {
    return _photoBytes[_photoNames[seed % _photoBytes.length]]!;
  }
  const palettes = [
    [(14, 116, 144), (250, 204, 21)],
    [(30, 64, 175), (244, 114, 182)],
    [(21, 128, 61), (190, 242, 100)],
    [(124, 45, 18), (251, 146, 60)],
    [(67, 56, 202), (125, 211, 252)],
    [(15, 23, 42), (148, 163, 184)],
  ];
  final [(r0, g0, b0), (r1, g1, b1)] = palettes[seed % palettes.length];
  final im = img.Image(width: 160, height: 160);
  for (var y = 0; y < 160; y++) {
    final t = y / 159;
    final c = img.ColorRgb8(
      (r0 + (r1 - r0) * t).round(),
      (g0 + (g1 - g0) * t).round(),
      (b0 + (b1 - b0) * t).round(),
    );
    img.drawLine(im, x1: 0, y1: y, x2: 159, y2: y, color: c);
  }
  img.fillCircle(
    im,
    x: 40 + (seed * 37) % 80,
    y: 52,
    radius: 18,
    color: img.ColorRgb8(255, 247, 220),
  );
  return img.encodeJpg(im, quality: 85);
}

/// Drive with the key on this device, 1.8 GB of the free 5 GB used, and the
/// index above; registered over whatever the previous preset left. On a
/// [phone], photo backup is on with most of the camera roll backed up.
void _registerDrive(String self, {required bool phone}) {
  final objects = _driveObjects();
  final live = objects.where((o) => o.trashedAt == null).toList();
  final dao = _Dao();
  List<VaultObject> files(bool Function(VaultObject) keep) =>
      live.where((o) => o.kind == 'file' && keep(o)).toList()
        ..sort((a, b) => b.mtime.compareTo(a.mtime));
  when(() => dao.watchChildren(any())).thenAnswer(
    (i) => Stream.value([
      for (final o in live)
        if (o.parent == i.positionalArguments.first) o,
    ]),
  );
  when(
    () => dao.watchRecent(limit: any(named: 'limit')),
  ).thenAnswer((_) => Stream.value(files((_) => true)));
  when(
    () => dao.watchFilesOfType(
      prefixes: any(named: 'prefixes'),
      types: any(named: 'types'),
    ),
  ).thenAnswer((i) {
    final prefixes = i.namedArguments[#prefixes] as List<String>? ?? const [];
    final types = i.namedArguments[#types] as List<String>? ?? const [];
    return Stream.value(
      files(
        (o) =>
            prefixes.any((p) => o.mime!.startsWith(p)) ||
            types.contains(o.mime),
      ),
    );
  });
  when(() => dao.watchLive()).thenAnswer((_) => Stream.value(live));
  when(() => dao.watchTrash()).thenAnswer((_) => Stream.value(const []));
  when(() => dao.watchChildCounts()).thenAnswer(
    (_) => Stream.value({
      for (final p in live.map((o) => o.parent).toSet())
        p: live.where((o) => o.parent == p).length,
    }),
  );
  when(() => dao.watchTransfers()).thenAnswer((_) => Stream.value(const []));
  when(() => dao.watchBackedUpAssets()).thenAnswer(
    (_) => Stream.value({
      for (var i = 6; i < 30; i++)
        if (i != 11) 'a$i': 'h$i',
    }),
  );
  when(() => dao.watchAssetUploads()).thenAnswer(
    (_) => Stream.value({'a2': 'uploading', 'a3': 'queued', 'a4': 'queued'}),
  );
  when(
    () => dao.liveFolders(),
  ).thenAnswer((_) async => live.where((o) => o.kind == 'dir').toList());
  when(() => dao.object(any())).thenAnswer(
    (i) async =>
        live.where((o) => o.id == i.positionalArguments.first).firstOrNull,
  );
  final db = _Db();
  when(() => db.vaultDao).thenReturn(dao);

  final copy = _KeyCopy();
  when(() => copy.holders).thenReturn(['google']);
  when(() => copy.stateOf(any())).thenReturn(KeyCopyState.saved);
  final account = _Account();
  when(() => account.status).thenReturn(VaultStatus.ready);
  when(() => account.load()).thenAnswer((_) async {});
  when(() => account.refreshInfo()).thenAnswer((_) async {});
  when(() => account.usedBytes).thenReturn(1843200000);
  final plan = Platform.environment['BISHARE_SHOTS_PLAN'];
  when(
    () => account.quotaBytes,
  ).thenReturn(plan == null ? 5000000000 : VaultPurchases.sizeOf(plan));
  when(() => account.keyCopy).thenReturn(copy);
  when(() => account.linkedProviders).thenReturn(['google']);
  when(() => account.infoLoaded).thenReturn(true);
  when(() => account.plan).thenReturn(plan ?? 'free');
  when(() => account.region).thenReturn('weur');
  when(() => account.reservedBytes).thenReturn(0);
  when(() => account.state).thenReturn(plan == null ? 'free' : 'active');
  when(
    () => account.planEnds,
  ).thenReturn(plan == null ? null : DateTime(2026, 11, 22));
  when(() => account.lapseEnds).thenReturn(null);
  when(
    () => account.planStore,
  ).thenReturn(plan == null ? null : VaultPurchases.storeHere);
  when(() => account.planRenews).thenReturn(plan == null ? null : true);
  when(() => account.vaultId).thenReturn('gtghb5lzztcv2lnacs3ldy7eni');
  // Windows: the code this computer shows until a phone approves it.
  final pairing = VaultDesktopPairing(
    slot: 'q3XbV0sLmQ8nT2rYc9fWkA',
    code: 'K7Q49MZD',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    qr:
        'BSVW1.q3XbV0sLmQ8nT2rYc9fWkA.'
        'Ek3pQm4vXn8Rt2Ys6Wd1Lf9Ha5Jc0Gb7Uo3Ie2Kz4Nq.'
        'Tq8Wm2Xd5Rv7Bn1Pk4Ls9Fh3Jy6Ga0Cu2Eo5Iz8Mb1Nx',
    secret: Uint8List(32),
  );
  registerFallbackValue(pairing);
  when(() => account.startDesktopPairing()).thenAnswer((_) async => pairing);
  when(() => account.checkDesktopPairing(any())).thenAnswer((_) async => false);
  when(() => account.cancelDesktopPairing(any())).thenAnswer((_) async {});
  // The plans at US prices, as the store would list them (task 7.1).
  final purchases = _Purchases();
  ProductDetails product(String id, String price, double raw) => ProductDetails(
    id: id,
    title: id,
    description: '',
    price: price,
    rawPrice: raw,
    currencyCode: 'USD',
  );
  when(() => purchases.products).thenReturn({
    for (final p in [
      product('drive_100gb_monthly', r'$2.49', 2.49),
      product('drive_100gb_yearly', r'$24.99', 24.99),
      product('drive_250gb_monthly', r'$5.99', 5.99),
      product('drive_250gb_yearly', r'$59.99', 59.99),
      product('drive_500gb_monthly', r'$9.99', 9.99),
      product('drive_500gb_yearly', r'$99.99', 99.99),
      product('drive_1tb_monthly', r'$19.99', 19.99),
      product('drive_1tb_yearly', r'$199.99', 199.99),
    ])
      p.id: p,
  });
  when(() => purchases.loading).thenReturn(false);
  when(() => purchases.available).thenReturn(true);
  when(() => purchases.busyProduct).thenReturn(null);
  when(() => purchases.restoring).thenReturn(false);
  when(() => purchases.lastError).thenReturn(null);
  when(purchases.load).thenAnswer((_) async {});
  final now = DateTime.now().millisecondsSinceEpoch;
  when(() => account.devices()).thenAnswer(
    (_) async => [
      VaultDeviceView(
        id: 'd1',
        name: self,
        thisDevice: true,
        web: self == 'Windows PC',
        computer: self == 'Windows PC',
        pending: false,
        addedAt: now,
        lastSeenAt: now,
      ),
      VaultDeviceView(
        id: 'd2',
        name: 'Leo',
        thisDevice: false,
        pending: false,
        addedAt: now,
        lastSeenAt: now - 3 * 60000,
      ),
      VaultDeviceView(
        id: 'd3',
        name: self == 'MacBook Pro' ? 'Office' : 'Studio',
        thisDevice: false,
        pending: false,
        addedAt: now,
        lastSeenAt: now - 26 * 3600000,
      ),
    ],
  );
  final sync = _Sync();
  when(sync.start).thenAnswer((_) async {});
  when(sync.pull).thenAnswer((_) async {});
  final uploader = _Uploader();
  when(uploader.run).thenAnswer((_) async {});
  final downloads = _Downloads();
  when(() => downloads.busy).thenReturn(false);
  final thumbs = _Thumbs();
  when(() => thumbs.load(any())).thenAnswer(
    (i) async => _thumb((i.positionalArguments.first as VaultObject).seq),
  );
  final backup = _Backup();
  final library = _Library();
  when(() => backup.available).thenReturn(phone);
  when(() => backup.library).thenReturn(library);
  when(() => backup.access).thenReturn(PhotoAccess.full);
  when(() => backup.on).thenReturn(true);
  when(() => backup.wifiOnly).thenReturn(true);
  when(() => backup.scanning).thenReturn(false);
  when(() => backup.left).thenReturn(7);
  when(() => backup.total).thenReturn(30);
  when(() => backup.noRoom).thenReturn(false);
  when(() => backup.gaveUp).thenReturn(0);
  when(
    () => backup.refreshAccess(ask: any(named: 'ask')),
  ).thenAnswer((_) async {});
  getIt
    ..registerSingleton<VaultPhotoBackup>(backup)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<VaultAccount>(account)
    ..registerSingleton<VaultPurchases>(purchases)
    ..registerSingleton<VaultSync>(sync)
    ..registerSingleton<VaultUploader>(uploader)
    ..registerSingleton<VaultDownloads>(downloads)
    ..registerSingleton<VaultThumbs>(thumbs);
}

/// The peers every screenshot shows: three devices that are not this one.
List<DiscoveredDevice> _cast(String self) {
  final now = DateTime.now();
  DiscoveredDevice peer(String fp, String alias, String type, int minutes) =>
      DiscoveredDevice(
        fingerprint: fp,
        alias: alias,
        host: '192.168.1.${20 + minutes}',
        port: 53317,
        lastSeen: now,
        firstSeen: now.subtract(Duration(minutes: minutes)),
        deviceModel: alias,
        deviceType: type,
        version: '2.6',
      );
  return [
    if (!self.startsWith('iPhone')) peer('fp-iphone', 'Nadia', 'mobile', 5),
    peer('fp-galaxy', 'Leo', 'mobile', 4),
    if (self != 'MacBook Pro') peer('fp-mac', 'Studio', 'desktop', 3),
    peer('fp-win', 'Office', 'desktop', 2),
  ].take(3).toList();
}

/// The name this device shows: a person's, never a maker's (Apple rejects
/// other brands in screenshots, and Play should match).
String _alias(String preset) => switch (preset) {
  'MacBook Pro' => 'Maya’s Mac',
  'Windows PC' => 'Maya’s PC',
  _ => 'Maya',
};

RoomState _room(String self) => RoomState(
  status: RoomStatus.inRoom,
  session: RoomSession(
    code: 'JK57',
    hostFingerprint: 'fp-self',
    hostAlias: self,
    isHost: true,
    hostToken: 'store-shot',
  ),
  members: const [
    // short names: the member row cuts labels after about seven letters
    RoomMember(fingerprint: 'fp-galaxy', alias: 'Leo', deviceType: 'mobile'),
    RoomMember(fingerprint: 'fp-mac', alias: 'Studio', deviceType: 'desktop'),
    RoomMember(fingerprint: 'fp-win', alias: 'Office', deviceType: 'desktop'),
  ],
  files: const [
    RoomFile(
      id: 'f1',
      fileName: 'IMG_2041.jpg',
      fileType: 'image/jpeg',
      size: 4718592,
      ownerFingerprint: 'fp-galaxy',
      ownerAlias: 'Leo',
    ),
    RoomFile(
      id: 'f2',
      fileName: 'Slides_Q4.pdf',
      fileType: 'application/pdf',
      size: 12582912,
      ownerFingerprint: 'fp-mac',
      ownerAlias: 'Studio',
    ),
    RoomFile(
      id: 'f3',
      fileName: 'VID_0412.mp4',
      fileType: 'video/mp4',
      size: 268435456,
      ownerFingerprint: 'fp-win',
      ownerAlias: 'Office',
    ),
  ],
  security: RoomSecurity.encrypted,
);

Future<void> _loadFonts(String? script) async {
  final manifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final name = family['family'] as String;
    final loader = FontLoader(name);
    if (name == AppTheme.fontFamily && script != null) {
      for (final w in [400, 500, 600, 700]) {
        final file = File(
          'store/screens/fonts/merged/IBMPlexSans+$script-$w.ttf',
        );
        loader.addFont(
          Future.value(ByteData.sublistView(file.readAsBytesSync())),
        );
      }
    } else {
      for (final font
          in (family['fonts'] as List).cast<Map<String, dynamic>>()) {
        // The manifest keeps the URL-encoded file name (`Geist%5Bwght%5D.ttf`).
        loader.addFont(
          rootBundle.load(Uri.decodeFull(font['asset'] as String)),
        );
      }
    }
    await loader.load();
  }
  final root =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/homebrew/share/flutter';
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
  }
}

/// The tab shell as MainShell draws it, around one page.
Widget _shell(BuildContext context, int index, Widget page) {
  // The app's tabs (main_shell.dart): Send, Inbox, Drive, Rooms, Settings.
  final items = [
    AppNavItem(icon: AppIcons.send, label: 'nav.tab_share'.tr()),
    AppNavItem(icon: AppIcons.notification, label: 'nav.tab_inbox'.tr()),
    AppNavItem(icon: AppIcons.cloudSync, label: 'vault.title'.tr()),
    AppNavItem(icon: AppIcons.teamGroup, label: 'nav.tab_rooms'.tr()),
    AppNavItem(icon: AppIcons.settings, label: 'nav.tab_settings'.tr()),
  ];
  final t = context.tokens;
  if (MediaQuery.sizeOf(context).width >= 760) {
    return Scaffold(
      backgroundColor: t.bg,
      body: Row(
        children: [
          AppNavRail(items: items, currentIndex: index, onTap: (_) {}),
          Expanded(child: page),
        ],
      ),
    );
  }
  return Scaffold(
    backgroundColor: t.bg,
    body: page,
    bottomNavigationBar: AppBottomNav(
      items: items,
      currentIndex: index,
      onTap: (_) {},
    ),
  );
}

/// The five screens, in store order: (file name, tab or null when pushed, page).
final List<(String, int?, Widget)> _screens = [
  ('1_share', 0, const HomePage()),
  ('2_inbox', 1, const InboxTab()),
  ('3_link', null, const RemoteSharePage()),
  ('5_settings', 4, const SettingsPage()),
];

/// Drive, in the Inbox tab (not framed for the stores, see the top): the
/// file manager as a list and as cards, the photos view as a gallery (the
/// view to tap; on phones the camera roll with its backup clouds and the
/// Drive's photos from other devices), and the account page.
final List<(String, int?, Widget, DriveView?)> _driveScreens = [
  ('drive/1_files', 1, const DrivePage(), null),
  ('drive/2_photos', 1, const DrivePage(), DriveView.media),
  ('drive/3_account', null, const VaultAccountPage(), null),
  ('drive/4_grid', 1, const DrivePage(), DriveView.files),
  // Also the App Store's review screenshot of the purchase screen (7.8).
  ('drive/6_plans', null, const DrivePlansPage(), null),
];

/// Windows and Linux only: the code a phone scans to approve this computer.
final List<(String, int?, Widget, DriveView?)> _desktopScreens = [
  ('drive/9_connect', null, const _ConnectPreview(), null),
];

/// The pairing sheet's content on a page, as the sheet shows it.
class _ConnectPreview extends StatelessWidget {
  const _ConnectPreview();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.bg,
      body: Center(
        child: Container(
          width: 460,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'vault.pair_title'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'vault.pair_body'.tr(
                  namedArgs: {
                    'manage': 'vault.manage'.tr(),
                    'open': 'vault.web_open'.tr(),
                  },
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
              const SizedBox(height: 16),
              const VaultDesktopPairingPanel(),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester, [int rounds = 12]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final dir = _dir;
  if (dir == null) {
    test('store screenshots skipped: BISHARE_SHOTS_DIR not set', () {});
    return;
  }
  final onlyLocales = _list('BISHARE_SHOTS_LOCALES');
  final onlyPresets = _list('BISHARE_SHOTS_PRESETS');

  final scripts = appLocales
      .map(_tag)
      .where((l) => onlyLocales.isEmpty || onlyLocales.contains(l))
      .map((l) => _scriptFont[l])
      .toSet();
  if (scripts.length > 1) {
    test('store screenshots: one language per run when it needs Noto glyphs '
        '(BISHARE_SHOTS_LOCALES), see store/screens/shoot.sh', () {
      fail('mixed scripts: $scripts');
    });
    return;
  }

  setUpAll(() async {
    registerFallbackValue(_driveObjects().first);
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableBuildModes = [];
    await EasyLocalization.ensureInitialized();
    await _loadFonts(scripts.single);
  });

  // One test for every preset: a second testWidgets in the same process
  // draws nothing but black (easy_localization never finishes loading there).
  testWidgets('store screenshots', (tester) async {
    addTearDown(tester.view.reset);
    // Soft shadows as on a device; the test binding draws them solid.
    debugDisableShadows = false;
    try {
      for (final MapEntry(key: name, value: preset) in {
        ..._presets,
        for (final e in _reviewPresets.entries)
          if (onlyPresets.contains(e.key)) e.key: e.value,
      }.entries) {
        if (onlyPresets.isNotEmpty && !onlyPresets.contains(name)) continue;
        debugDefaultTargetPlatformOverride = preset.platform;
        try {
          await _run(tester, dir, name, preset, onlyLocales);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    } finally {
      debugDisableShadows = true;
    }
  });
}

Future<void> _run(
  WidgetTester tester,
  String dir,
  String name,
  _Preset preset,
  List<String> onlyLocales,
) async {
  final ratio = preset.ratio;
  tester.view
    ..physicalSize = preset.size * ratio
    ..devicePixelRatio = ratio
    ..padding = FakeViewPadding(
      top: preset.insets.top * ratio,
      bottom: preset.insets.bottom * ratio,
    )
    ..viewPadding = FakeViewPadding(
      top: preset.insets.top * ratio,
      bottom: preset.insets.bottom * ratio,
    );

  await tester.runAsync(() async {
    await GetIt.instance.reset();
    await _loadPhotos();
    SendMediaLibrary.instance = _FakeLibrary();
    final prefs = await SharedPreferences.getInstance();
    final (crypto, _) = await E2ECrypto.create();
    getIt
      ..registerSingleton<SharedPreferences>(prefs)
      ..registerSingleton<DesktopService>(_desktop())
      // no cached flags: Drive off, so Settings is the one in the stores
      ..registerSingleton<FeatureFlags>(FeatureFlags(prefs))
      ..registerSingleton<DeviceIdentity>(
        DeviceIdentity.forTesting(
          fingerprint: 'fp-self',
          alias: _alias(preset.self),
          crypto: crypto,
          deviceModel: preset.self,
          deviceType: preset.type,
          prefs: prefs,
        ),
      );
  });
  final phone =
      preset.platform == TargetPlatform.android ||
      preset.platform == TargetPlatform.iOS;
  _registerDrive(preset.self, phone: phone);
  final showcase = registerAppShowcase();

  final settings = _Settings();
  whenListen(
    settings,
    const Stream<Settings>.empty(),
    initialState: Settings(alias: _alias(preset.self), themeMode: _theme),
  );
  when(() => settings.canPickSaveFolder).thenReturn(preset.type == 'desktop');
  when(() => settings.clipboardImagesSupported).thenReturn(true);
  when(() => settings.currentSaveDir).thenReturn('~/Documents/BIShare');
  final tray = _Tray();
  whenListen(
    tray,
    const Stream<List<SendableFile>>.empty(),
    initialState: const <SendableFile>[],
  );
  when(() => tray.totalBytes).thenReturn(0);
  final discovery = _Discovery();
  whenListen(
    discovery,
    const Stream<List<DiscoveredDevice>>.empty(),
    initialState: _cast(_alias(preset.self)),
  );
  final receive = _Receive();
  whenListen(
    receive,
    const Stream<ReceiveState>.empty(),
    initialState: const ReceiveState(),
  );
  final send = _Send();
  whenListen(
    send,
    const Stream<SendState>.empty(),
    initialState: const SendState(),
  );
  final favorites = _Favorites();
  whenListen(
    favorites,
    const Stream<Map<String, FavoriteDevice>>.empty(),
    initialState: const <String, FavoriteDevice>{},
  );
  final room = _Room();
  whenListen(
    room,
    const Stream<RoomState>.empty(),
    initialState: _room(_alias(preset.self)),
  );
  final webNearby = _WebNearby();
  whenListen(
    webNearby,
    const Stream<WebNearbyState>.empty(),
    initialState: const WebNearbyState(),
  );

  final inbox = _Inbox();
  // Everything already seen: no "new" dots on the shots.
  when(() => inbox.seenAt).thenReturn(ValueNotifier(DateTime(2027)));
  whenListen(
    inbox,
    const Stream<List<TransferRecord>>.empty(),
    initialState: _received(),
  );
  final history = _History();
  whenListen(
    history,
    const Stream<HistoryState>.empty(),
    initialState: HistoryState(all: _received()),
  );

  final boundary = GlobalKey();
  final locales = appLocales
      .where((l) => onlyLocales.isEmpty || onlyLocales.contains(_tag(l)))
      .toList();
  for (final locale in locales) {
    final lang = _tag(locale);
    for (final (file, tab, page, view) in <(String, int?, Widget, DriveView?)>[
      for (final (file, tab, page) in _screens) (file, tab, page, null),
      ('4_drive', 2, const DrivePage(), phone ? DriveView.media : null),
      ..._driveScreens,
      if (preset.platform == TargetPlatform.windows) ..._desktopScreens,
    ]) {
      final only = _list('BISHARE_SHOTS_ONLY');
      if (only.isNotEmpty && !only.any(file.contains)) continue;
      // Drive keeps list or grid in the preferences: the views get the grid
      await tester.runAsync(
        () => getIt<SharedPreferences>().setBool('vault.grid', view != null),
      );
      final router = GoRouter(
        initialLocation: tab == null ? '/page' : '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) =>
                tab == null ? const SizedBox() : _shell(context, tab, page),
            routes: [
              if (tab == null)
                GoRoute(path: 'page', builder: (context, _) => page),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: EasyLocalization(
            key: ValueKey('$name/$lang/$file'),
            supportedLocales: appLocales,
            path: 'assets/translations',
            fallbackLocale: appFallbackLocale,
            useFallbackTranslations: true,
            startLocale: locale,
            saveLocale: false,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<DiscoveryCubit>.value(value: discovery),
                BlocProvider<ReceiveCubit>.value(value: receive),
                BlocProvider<SendCubit>.value(value: send),
                BlocProvider<TrayCubit>.value(value: tray),
                BlocProvider<SendSelectionCubit>(
                  // Three photos chosen on a phone, so the Send bar shows;
                  // computers have no library to choose from.
                  create: (_) {
                    final c = SendSelectionCubit(tray);
                    if (SendMediaLibrary.available) {
                      c.setAssets(
                        (SendMediaLibrary.instance as _FakeLibrary).assets
                            .take(3)
                            .toList(),
                        SendKind.photo,
                        true,
                      );
                    }
                    return c;
                  },
                ),
                BlocProvider<FavoritesCubit>.value(value: favorites),
                BlocProvider<RoomCubit>.value(value: room),
                BlocProvider<SettingsCubit>.value(value: settings),
                BlocProvider<InboxCubit>.value(value: inbox),
                BlocProvider<HistoryCubit>.value(value: history),
                BlocProvider<WebNearbyCubit>.value(value: webNearby),
              ],
              child: Builder(
                builder: (context) => MaterialApp.router(
                  title: 'BIShare',
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  theme: AppTheme.light('blue'),
                  darkTheme: AppTheme.dark('blue'),
                  themeMode: _theme,
                  routerConfig: router,
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      if (view != null) {
        // Phones show Drive's tabs (Photos, Files, ...); a computer, the
        // sidebar's views.
        final label = switch (view) {
          DriveView.media when phone => 'vault.tab_photos'.tr(),
          DriveView.files when phone => 'vault.tab_files'.tr(),
          _ => driveViewLabel(view),
        };
        final target = find.text(label);
        if (target.evaluate().isNotEmpty) {
          await tester.ensureVisible(target.first);
          await _settle(tester);
          await tester.tap(target.first);
          await _settle(tester);
        }
      }
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: ratio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        (File('$dir/$name/$lang/$file.png')..parent.createSync(recursive: true))
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      router.dispose();
    }
  }
  showcase.unregister();
}
