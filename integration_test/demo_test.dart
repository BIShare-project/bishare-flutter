import 'package:bishare/app/router.dart';
import 'package:bishare/core/ui/app_media_tile.dart';
import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/features/onboarding/presentation/onboarding_page.dart';
import 'package:bishare/main.dart' as app;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A scripted walk through the app for the promo video: the Simulator's
/// screen is recorded while this runs (video/windows-trailer/record_ios.sh),
/// and each step prints a DEMO marker with the wall-clock time, so the
/// video can be cut to the same moments.
///
///   flutter test integration_test/demo_test.dart -d SIMULATOR_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> hold(WidgetTester tester, int ms) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void mark(String step) =>
      // ignore: avoid_print
      print('DEMO $step ${DateTime.now().millisecondsSinceEpoch}');

  Future<void> tapText(WidgetTester tester, String key) async {
    await tester.tap(find.text(key.tr()).last);
  }

  testWidgets('demo walk', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDone, true);
    for (final id in [ShowcaseIds.home, ShowcaseIds.inbox, ShowcaseIds.rooms]) {
      await prefs.setBool(id, true);
    }
    await app.main();
    await hold(tester, 6000);

    // Send: the gallery, three photos chosen one by one.
    mark('send');
    await hold(tester, 1800);
    final tiles = find.byType(AppMediaTile);
    for (var i = 0; i < 3 && i < tiles.evaluate().length; i++) {
      await tester.tap(tiles.at(i));
      await hold(tester, 650);
    }
    mark('chosen');
    await hold(tester, 2200);

    // The other kinds: Videos, Documents, then back to Photos.
    mark('tabs');
    await tapText(tester, 'compose.tab_video');
    await hold(tester, 1400);
    await tapText(tester, 'compose.tab_documents');
    await hold(tester, 1400);
    await tapText(tester, 'home.photos');
    await hold(tester, 1200);

    // Secure Link.
    mark('link');
    appRouter.push('/remote');
    await hold(tester, 3600);
    appRouter.pop();
    await hold(tester, 900);

    // QR Beam.
    mark('beam');
    appRouter.push('/qr-beam');
    await hold(tester, 2800);
    appRouter.pop();
    await hold(tester, 900);

    // Rooms.
    mark('rooms');
    await tapText(tester, 'nav.tab_rooms');
    await hold(tester, 2800);

    // Settings, scrolled slowly.
    mark('settings');
    await tapText(tester, 'nav.tab_settings');
    await hold(tester, 1500);
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await hold(tester, 700);
    }
    mark('end');
    await hold(tester, 1000);
  });
}
