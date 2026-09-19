import 'package:bishare/core/telemetry/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server adds these flags up without knowing who sent them, so the
/// counting is only right if each install sends `day` once per UTC day and
/// `month` once per thirty days. These tests pin that.
void main() {
  final noon = DateTime.utc(2026, 9, 19, 12);
  int msAgo(Duration d) => noon.subtract(d).millisecondsSinceEpoch;

  test('a fresh install reports both', () {
    final f = TelemetryService.activeFlags(lastDay: null, lastMonthAtMs: null, now: noon);
    expect(f.day, isTrue);
    expect(f.month, isTrue);
  });

  test('a second launch the same UTC day reports nothing', () {
    final f = TelemetryService.activeFlags(
      lastDay: '2026-09-19',
      lastMonthAtMs: msAgo(const Duration(hours: 3)),
      now: noon,
    );
    expect(f.day, isFalse);
    expect(f.month, isFalse);
  });

  test('the next day reports day only', () {
    final f = TelemetryService.activeFlags(
      lastDay: '2026-09-18',
      lastMonthAtMs: msAgo(const Duration(days: 1)),
      now: noon,
    );
    expect(f.day, isTrue);
    expect(f.month, isFalse);
  });

  test('month is due at thirty days, not before', () {
    final before = TelemetryService.activeFlags(
      lastDay: '2026-08-20',
      lastMonthAtMs: msAgo(const Duration(days: 29, hours: 23)),
      now: noon,
    );
    expect(before.month, isFalse);
    final at = TelemetryService.activeFlags(
      lastDay: '2026-08-20',
      lastMonthAtMs: msAgo(const Duration(days: 30)),
      now: noon,
    );
    expect(at.month, isTrue);
  });

  test('the day is the UTC day, whatever the local zone says', () {
    // 23:30 in UTC-5 on the 18th is already 04:30 UTC on the 19th.
    final local = DateTime.utc(2026, 9, 19, 4, 30).toLocal();
    final f = TelemetryService.activeFlags(
      lastDay: '2026-09-19',
      lastMonthAtMs: msAgo(const Duration(days: 2)),
      now: local,
    );
    expect(f.day, isFalse);
  });

  test('a clock set backwards does not earn a second month flag', () {
    final f = TelemetryService.activeFlags(
      lastDay: '2026-09-19',
      lastMonthAtMs: noon.add(const Duration(days: 5)).millisecondsSinceEpoch,
      now: noon,
    );
    expect(f.month, isFalse);
  });
}
