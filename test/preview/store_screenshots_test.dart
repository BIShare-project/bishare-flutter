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
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bishare/core/crypto/e2e_crypto.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/identity/device_identity.dart';
import 'package:bishare/core/l10n/app_locales.dart';
import 'package:bishare/core/storage/app_database.dart';
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

String _tag(Locale l) =>
    l.countryCode == null ? l.languageCode : '${l.languageCode}-${l.countryCode}';

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
        final file = File('store/screens/fonts/merged/IBMPlexSans+$script-$w.ttf');
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
    await (FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
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
  whenListen(tray, const Stream<List<SendableFile>>.empty(), initialState: const <SendableFile>[]);
  when(() => tray.totalBytes).thenReturn(0);
  final discovery = _Discovery();
  whenListen(
    discovery,
    const Stream<List<DiscoveredDevice>>.empty(),
    initialState: _cast(preset.self),
  );
  final receive = _Receive();
  whenListen(receive, const Stream<ReceiveState>.empty(), initialState: const ReceiveState());
  final send = _Send();
  whenListen(send, const Stream<SendState>.empty(), initialState: const SendState());
  final favorites = _Favorites();
  whenListen(
    favorites,
    const Stream<Map<String, FavoriteDevice>>.empty(),
    initialState: const <String, FavoriteDevice>{},
  );
  final room = _Room();
  whenListen(room, const Stream<RoomState>.empty(), initialState: _room(preset.self));
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
    for (final (file, tab, page) in _screens) {
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
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: ratio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final out = Directory('$dir/$name/$lang')..createSync(recursive: true);
        File('${out.path}/$file.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      router.dispose();
    }
  }
  showcase.unregister();
}
