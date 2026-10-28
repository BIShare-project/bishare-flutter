import 'package:bishare/app/router.dart';
import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/di/locator.dart';
import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/features/clipboard/presentation/clipboard_history_page.dart';
import 'package:bishare/features/devices/presentation/devices_page.dart';
import 'package:bishare/features/file_manager/presentation/file_manager_page.dart';
import 'package:bishare/features/history/presentation/history_page.dart';
import 'package:bishare/features/home/home_page.dart';
import 'package:bishare/features/home/widgets/device_section.dart';
import 'package:bishare/features/home/widgets/send_list_tabs.dart';
import 'package:bishare/features/home/widgets/send_media_tab.dart';
import 'package:bishare/features/inbox/presentation/inbox_page.dart';
import 'package:bishare/features/inbox/presentation/widgets/web_access_body.dart';
import 'package:bishare/features/onboarding/presentation/onboarding_page.dart';
import 'package:bishare/features/qr_beam/presentation/qr_beam_page.dart';
import 'package:bishare/features/qr_beam/presentation/qr_beam_send_page.dart';
import 'package:bishare/features/remote/presentation/remote_share_page.dart';
import 'package:bishare/features/room/presentation/room_page.dart';
import 'package:bishare/features/settings/presentation/settings_page.dart';
import 'package:bishare/features/vault/presentation/drive/drive_page.dart';
import 'package:bishare/main.dart' as app;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phase 2 gate (redesign-plan.md): every destination of the feature
/// map opens from the new navigation, in the real app on a device.
///
///   flutter test integration_test/nav_test.dart -d emulator-5554
///
/// Finders use the translation keys, so the device language does not matter.
/// Pages that need a camera (scan, QR Beam receive), Apple only (Nearby) or a
/// signed-in Drive are left to their own phases.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The radar and pulses never settle; pump a fixed time instead.
  Future<void> settle(WidgetTester tester, [int ms = 1200]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapText(WidgetTester tester, String key) async {
    await tester.tap(find.text(key.tr()).last);
    await settle(tester);
  }

  Future<void> closeTop(WidgetTester tester) async {
    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    await nav.maybePop();
    await settle(tester);
  }

  testWidgets('every destination opens from the navigation', (tester) async {
    // A finished onboarding and finished tours, so nothing covers the tabs.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDone, true);
    for (final id in [ShowcaseIds.home, ShowcaseIds.inbox, ShowcaseIds.rooms]) {
      await prefs.setBool(id, true);
    }
    await app.main();
    await settle(tester, 4000);

    // Kirim and its six content tabs.
    expect(find.byType(HomePage), findsOneWidget);
    final tabs = <String, Type>{
      'home.photos': SendMediaTab,
      'compose.tab_video': SendMediaTab,
      'compose.tab_audio': SendAudioTab,
      'home.apps': SendAppsTab,
      'compose.tab_documents': SendDocsTab,
      'compose.tab_more': SendMoreTab,
    };
    for (final MapEntry(:key, :value) in tabs.entries) {
      if (find.text(key.tr()).evaluate().isEmpty) continue; // Apps: Android
      await tapText(tester, key);
      expect(find.byType(value), findsWidgets, reason: key);
    }

    // The device list sheet from the header's visibility line.
    await tester.tap(find.textContaining('compose.visible'.tr()).first);
    await settle(tester);
    expect(find.byType(DeviceSection), findsOneWidget);
    await closeTop(tester);

    // Kotak Masuk: Received, History, the menu's Files and Browser access.
    await tapText(tester, 'nav.tab_inbox');
    expect(find.byType(InboxPage), findsOneWidget);
    // The menu shows once something was received; an empty Inbox offers
    // Browser access in its empty state instead.
    final menu = find.byTooltip('inbox.more'.tr());
    if (menu.evaluate().isNotEmpty) {
      await tester.tap(menu.first);
      await settle(tester);
      await tapText(tester, 'inbox.browse_files');
      expect(find.byType(FileManagerPage), findsOneWidget);
      await closeTop(tester);
      await tester.tap(menu.first);
      await settle(tester);
    }
    await tapText(tester, 'inbox.browser_access');
    expect(find.byType(WebAccessBody), findsOneWidget);
    await closeTop(tester);
    await tapText(tester, 'history.title');
    expect(find.byType(HistoryPage), findsOneWidget);

    // Drive (only while its flag shows it), Ruangan, Pengaturan.
    if (getIt<FeatureFlags>().vaultVisible) {
      await tapText(tester, 'vault.title');
      expect(find.byType(DrivePage), findsOneWidget);
    }
    await tapText(tester, 'nav.tab_rooms');
    expect(find.byType(RoomPage), findsOneWidget);
    await tapText(tester, 'nav.tab_settings');
    expect(find.byType(SettingsPage), findsOneWidget);

    // Pushed pages.
    final pages = <String, Type>{
      '/devices': DevicesPage,
      '/clipboard': ClipboardHistoryPage,
      '/remote': RemoteSharePage,
      '/qr-beam': QrBeamPage,
      '/qr-beam/send': QrBeamSendPage,
      '/files': FileManagerPage,
    };
    for (final MapEntry(:key, :value) in pages.entries) {
      appRouter.push(key);
      await settle(tester);
      expect(find.byType(value), findsOneWidget, reason: key);
      appRouter.pop();
      await settle(tester);
    }
  });
}
