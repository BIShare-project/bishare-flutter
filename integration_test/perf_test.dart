import 'package:bishare/core/ui/app_showcase.dart';
import 'package:bishare/features/home/widgets/send_media_tab.dart';
import 'package:bishare/features/inbox/presentation/inbox_page.dart';
import 'package:bishare/features/onboarding/presentation/onboarding_page.dart';
import 'package:bishare/main.dart' as app;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Frame timings of the redesigned screens (redesign-plan.md "Performance
/// budget"), in profile mode on a real phone:
///
///   flutter drive --profile --driver=test_driver/perf_driver.dart \
///     --target=integration_test/perf_test.dart -d DEVICE_ID
///
/// One timeline per scenario; the driver writes build/perf/summary.txt.
/// P3 (drag select), P4 (a send) and P6 (Drive backup) need a second device
/// or a signed-in Drive and are not here yet.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frames at the display's own pace, not the test's.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> tapText(WidgetTester tester, String key, {int ms = 700}) async {
    final target = find.text(key.tr()).last;
    // A tab scrolled off the strip comes back into view first.
    await tester.ensureVisible(target);
    await wait(300);
    await tester.tap(target);
    await wait(ms);
  }

  /// The vertical list of [page] (not a tab strip or a chip row).
  Finder scrollableIn(Type page) => find
      .descendant(
        of: find.byType(page).hitTestable().first,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;

  /// The engine's own frame times (FrameTiming), which see every frame; the
  /// timeline the driver summarises misses some under load. One line per
  /// scenario in the log and in the report data under "engine".
  final engine = <String, Object>{};
  Future<void> measure(String key, Future<void> Function() action) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);
    final clock = Stopwatch()..start();
    await binding.traceAction(action, reportKey: key);
    // The last frames arrive in the next batch.
    await wait(1200);
    clock.stop();
    SchedulerBinding.instance.removeTimingsCallback(collect);
    double p(List<double> v, double q) =>
        v.isEmpty ? 0 : v[((v.length - 1) * q).round()];
    List<double> ms(Duration Function(FrameTiming) f) =>
        [for (final t in timings) f(t).inMicroseconds / 1000]..sort();
    final build = ms((t) => t.buildDuration);
    final raster = ms((t) => t.rasterDuration);
    final total = ms((t) => t.totalSpan);
    const budget = 1000 / 90;
    String f(double v) => v.toStringAsFixed(1);
    final line =
        '$key: ${timings.length} frames / ${clock.elapsedMilliseconds} ms; '
        'build p90 ${f(p(build, .9))} worst ${f(p(build, 1))}; '
        'raster p90 ${f(p(raster, .9))} worst ${f(p(raster, 1))}; '
        'total p90 ${f(p(total, .9))} worst ${f(p(total, 1))}; '
        'over 11.1 ms: build ${build.where((v) => v > budget).length}, '
        'raster ${raster.where((v) => v > budget).length}; '
        'over 32 ms total: ${total.where((v) => v > 32).length}';
    debugPrint('[perf] $line');
    engine[key] = line;
  }

  tearDownAll(
    () => binding.reportData = {...?binding.reportData, 'engine': engine},
  );

  testWidgets('frame timings', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDone, true);
    for (final id in [ShowcaseIds.home, ShowcaseIds.inbox, ShowcaseIds.rooms]) {
      await prefs.setBool(id, true);
    }
    await app.main();
    await wait(6000);

    // P8: every bottom tab, twice.
    await measure('p8_bottom_tabs', () async {
      for (var round = 0; round < 2; round++) {
        for (final key in [
          'nav.tab_inbox',
          'vault.title',
          'nav.tab_rooms',
          'nav.tab_settings',
          'nav.tab_share',
        ]) {
          if (find.text(key.tr()).evaluate().isEmpty) continue;
          await tapText(tester, key);
        }
      }
    });

    // P2: the six Kirim tabs, twice.
    await measure('p2_send_tabs', () async {
      for (var round = 0; round < 2; round++) {
        for (final key in [
          'compose.tab_video',
          'compose.tab_audio',
          'home.apps',
          'compose.tab_documents',
          'compose.tab_more',
          'home.photos',
        ]) {
          if (find.text(key.tr()).evaluate().isEmpty) continue;
          await tapText(tester, key, ms: 900);
        }
      }
    });

    // P1: the photo grid, flung down and back up.
    await wait(1500);
    await measure('p1_photo_scroll', () async {
      final grid = scrollableIn(SendMediaTab);
      for (var i = 0; i < 8; i++) {
        await tester.fling(grid, const Offset(0, -900), 4000);
        await wait(700);
      }
      final moved = tester.state<ScrollableState>(grid).position.pixels;
      debugPrint('[perf] photo grid scrolled to $moved px');
      expect(moved, greaterThan(2000), reason: 'the grid did not scroll');
      for (var i = 0; i < 8; i++) {
        await tester.fling(grid, const Offset(0, 900), 4000);
        await wait(700);
      }
    });

    // P7: the device list sheet, opened and closed five times.
    await measure('p7_sheets', () async {
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.textContaining('compose.visible'.tr()).first);
        await wait(700);
        await tester
            .state<NavigatorState>(find.byType(Navigator).last)
            .maybePop();
        await wait(700);
      }
    });

    // P5: the Inbox, flung down and up.
    await tapText(tester, 'nav.tab_inbox', ms: 1500);
    await measure('p5_inbox_scroll', () async {
      final list = scrollableIn(InboxPage);
      for (var i = 0; i < 4; i++) {
        await tester.fling(list, const Offset(0, -700), 3000);
        await wait(700);
        await tester.fling(list, const Offset(0, 700), 3000);
        await wait(700);
      }
    });
  });
}
