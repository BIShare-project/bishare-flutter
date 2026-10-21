// Store screenshots, not goldens: renders the real BIShare screens on the
// host — no simulator, no emulator — at the sizes the stores ask for, to PNG
// files. Runs only when BISHARE_SHOTS_DIR is set; store/screens/shoot.sh runs
// it once per language and then frames the results:
//
//   BISHARE_SHOTS_DIR=/tmp/raw BISHARE_SHOTS_LOCALES=ja \
//     flutter test test/preview/store_screenshots_test.dart
//
// Optional: BISHARE_SHOTS_PRESETS=ios_phone,mac. Output:
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
// frame.py does not read: Drive is not in the stores' screenshots while it is
// in testing, but every language is checked for overflows and missing keys.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/l10n/app_locales.dart';
import 'package:bishare/core/storage/app_database.dart';
import 'package:bishare/core/storage/vault_tables.dart';
import 'package:bishare/core/theme/app_theme.dart';
import 'package:bishare/core/ui/app_bottom_nav.dart';
import 'package:bishare/core/ui/app_nav_rail.dart';
import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/core/ui/app_svg_icon.dart';
import 'package:bishare/features/discovery/domain/discovered_device.dart';
import 'package:bishare/features/discovery/presentation/discovery_cubit.dart';
import 'package:bishare/features/favorites/presentation/favorites_cubit.dart';
import 'package:bishare/features/home/home_page.dart';
import 'package:bishare/features/qr_beam/presentation/qr_beam_page.dart';
import 'package:bishare/features/receive/presentation/receive_cubit.dart';
import 'package:bishare/features/remote/presentation/remote_share_page.dart';
import 'package:bishare/features/room/domain/room_models.dart';
import 'package:bishare/features/room/presentation/room_cubit.dart';
import 'package:bishare/features/room/presentation/room_page.dart';
import 'package:bishare/features/send/domain/sendable_file.dart';
import 'package:bishare/features/send/presentation/send_cubit.dart';
import 'package:bishare/features/send/presentation/tray_cubit.dart';
import 'package:bishare/features/settings/domain/settings.dart';
import 'package:bishare/features/settings/presentation/settings_cubit.dart';
import 'package:bishare/features/settings/presentation/settings_page.dart';
import 'package:bishare/features/vault/data/vault_account.dart';
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
import 'package:shadcn_ui/shadcn_ui.dart';
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

class _Account extends Mock implements VaultAccount {}

class _KeyCopy extends Mock implements VaultKeyCopy {}

class _Sync extends Mock implements VaultSync {}

class _Uploader extends Mock implements VaultUploader {}

class _Downloads extends Mock implements VaultDownloads {}

class _Thumbs extends Mock implements VaultThumbs {}

class _Backup extends Mock implements VaultPhotoBackup {}

/// A phone's camera roll: 30 photos and videos, newest first.
class _Library implements PhotoLibrary {
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
  when(() => account.quotaBytes).thenReturn(5000000000);
  when(() => account.keyCopy).thenReturn(copy);
  when(() => account.linkedProviders).thenReturn(['google']);
  when(() => account.infoLoaded).thenReturn(true);
  when(() => account.plan).thenReturn('free');
  when(() => account.region).thenReturn('weur');
  when(() => account.reservedBytes).thenReturn(0);
  final now = DateTime.now().millisecondsSinceEpoch;
  when(() => account.devices()).thenAnswer(
    (_) async => [
      VaultDeviceView(
        id: 'd1',
        name: self,
        thisDevice: true,
        pending: false,
        addedAt: now,
        lastSeenAt: now,
      ),
      VaultDeviceView(
        id: 'd2',
        name: 'Galaxy S25',
        thisDevice: false,
        pending: false,
        addedAt: now,
        lastSeenAt: now - 3 * 60000,
      ),
      VaultDeviceView(
        id: 'd3',
        name: self == 'MacBook Pro' ? 'Windows PC' : 'MacBook Pro',
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
  when(
    () => backup.refreshAccess(ask: any(named: 'ask')),
  ).thenAnswer((_) async {});
  getIt
    ..registerSingleton<VaultPhotoBackup>(backup)
    ..registerSingleton<AppDatabase>(db)
    ..registerSingleton<VaultAccount>(account)
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
    if (!self.startsWith('iPhone')) peer('fp-iphone', 'iPhone 17', 'mobile', 5),
    peer('fp-galaxy', 'Galaxy S25', 'mobile', 4),
    if (self != 'MacBook Pro') peer('fp-mac', 'MacBook Pro', 'desktop', 3),
    peer('fp-win', 'Windows PC', 'desktop', 2),
  ].take(3).toList();
}

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
    RoomMember(fingerprint: 'fp-galaxy', alias: 'Galaxy', deviceType: 'mobile'),
    RoomMember(fingerprint: 'fp-mac', alias: 'MacBook', deviceType: 'desktop'),
    RoomMember(fingerprint: 'fp-win', alias: 'Surface', deviceType: 'desktop'),
  ],
  files: const [
    RoomFile(
      id: 'f1',
      fileName: 'IMG_2041.jpg',
      fileType: 'image/jpeg',
      size: 4718592,
      ownerFingerprint: 'fp-galaxy',
      ownerAlias: 'Galaxy',
    ),
    RoomFile(
      id: 'f2',
      fileName: 'Slides_Q4.pdf',
      fileType: 'application/pdf',
      size: 12582912,
      ownerFingerprint: 'fp-mac',
      ownerAlias: 'MacBook',
    ),
    RoomFile(
      id: 'f3',
      fileName: 'VID_0412.mp4',
      fileType: 'video/mp4',
      size: 268435456,
      ownerFingerprint: 'fp-win',
      ownerAlias: 'Surface',
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
  final items = [
    AppNavItem(icon: AppIcons.shareLink, label: 'nav.tab_share'.tr()),
    AppNavItem(icon: AppIcons.notification, label: 'nav.tab_inbox'.tr()),
    AppNavItem(icon: AppIcons.teamGroup, label: 'nav.tab_rooms'.tr()),
    AppNavItem(icon: AppIcons.history, label: 'nav.tab_history'.tr()),
    AppNavItem(icon: AppIcons.settings, label: 'nav.tab_settings'.tr()),
  ];
  final cs = ShadTheme.of(context).colorScheme;
  if (MediaQuery.sizeOf(context).width >= 760) {
    return Scaffold(
      backgroundColor: cs.background,
      body: Row(
        children: [
          AppNavRail(items: items, currentIndex: index, onTap: (_) {}),
          Expanded(child: page),
        ],
      ),
    );
  }
  return Scaffold(
    backgroundColor: cs.background,
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
  ('2_link', null, const RemoteSharePage()),
  ('3_qr_beam', null, const QrBeamPage()),
  ('4_rooms', 2, const RoomPage()),
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
];

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
    for (final MapEntry(key: name, value: preset) in _presets.entries) {
      if (onlyPresets.isNotEmpty && !onlyPresets.contains(name)) continue;
      debugDefaultTargetPlatformOverride = preset.platform;
      try {
        await _run(tester, dir, name, preset, onlyLocales);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
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
    final prefs = await SharedPreferences.getInstance();
    final (crypto, _) = await E2ECrypto.create();
    getIt
      ..registerSingleton<SharedPreferences>(prefs)
      // no cached flags: Drive off, so Settings is the one in the stores
      ..registerSingleton<FeatureFlags>(FeatureFlags(prefs))
      ..registerSingleton<DeviceIdentity>(
        DeviceIdentity.forTesting(
          fingerprint: 'fp-self',
          alias: preset.self,
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
    initialState: Settings(alias: preset.self, themeMode: ThemeMode.dark),
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
    initialState: _cast(preset.self),
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
    initialState: _room(preset.self),
  );
  final webNearby = _WebNearby();
  whenListen(
    webNearby,
    const Stream<WebNearbyState>.empty(),
    initialState: const WebNearbyState(),
  );

  final boundary = GlobalKey();
  final locales = appLocales
      .where((l) => onlyLocales.isEmpty || onlyLocales.contains(_tag(l)))
      .toList();
  for (final locale in locales) {
    final lang = _tag(locale);
    for (final (file, tab, page, view) in <(String, int?, Widget, DriveView?)>[
      for (final (file, tab, page) in _screens) (file, tab, page, null),
      ..._driveScreens,
    ]) {
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
                BlocProvider<FavoritesCubit>.value(value: favorites),
                BlocProvider<RoomCubit>.value(value: room),
                BlocProvider<SettingsCubit>.value(value: settings),
                BlocProvider<WebNearbyCubit>.value(value: webNearby),
              ],
              child: Builder(
                builder: (context) => ShadApp.router(
                  title: 'BIShare',
                  debugShowCheckedModeBanner: false,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  theme: AppTheme.light('blue'),
                  darkTheme: AppTheme.dark('blue'),
                  themeMode: ThemeMode.dark,
                  materialThemeBuilder: (context, theme) => theme.copyWith(
                    textTheme: theme.textTheme.apply(
                      fontFamily: AppTheme.fontFamily,
                    ),
                  ),
                  routerConfig: router,
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      if (view != null) {
        // The chips scroll sideways: the later ones start off screen.
        await tester.ensureVisible(find.text(driveViewLabel(view)).first);
        await _settle(tester);
        await tester.tap(find.text(driveViewLabel(view)).first);
        await _settle(tester);
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
