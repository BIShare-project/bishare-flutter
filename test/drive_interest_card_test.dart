import 'package:bishare/core/config/feature_flags.dart';
import 'package:bishare/core/telemetry/telemetry_service.dart';
import 'package:bishare/features/home/widgets/drive_interest_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Flags extends FeatureFlags {
  _Flags(super.prefs, this.on);
  bool on;
  @override
  bool get driveInterestEnabled => on;
}

class _Telemetry extends TelemetryService {
  _Telemetry(super.prefs, {this.on = true});
  final bool on;
  final events = <String>[];
  @override
  bool get enabled => on;
  @override
  void recordInterest(String event, {String topic = 'drive'}) => events.add(event);
}

/// The question is only worth asking if it is asked once, counted once, and
/// never shown to someone it should not reach. These tests pin that.
void main() {
  group('shouldShow', () {
    bool show({bool flag = true, bool telemetry = true, int launches = 2, String? answer}) =>
        DriveInterestCard.shouldShow(
          flagOn: flag,
          telemetryOn: telemetry,
          launches: launches,
          answer: answer,
        );

    test('shown from the second launch with the flag on', () => expect(show(), isTrue));
    test('not on the first launch', () => expect(show(launches: 1), isFalse));
    test('not with the flag off', () => expect(show(flag: false), isFalse));
    test('not when usage statistics are off', () => expect(show(telemetry: false), isFalse));
    test('not after any answer', () {
      for (final a in ['yes_paid', 'yes_free', 'no', 'dismiss']) {
        expect(show(answer: a), isFalse, reason: a);
      }
    });
  });

  Future<(SharedPreferences, _Telemetry)> pump(
    WidgetTester tester, {
    bool flag = true,
    bool telemetry = true,
    Map<String, Object> stored = const {},
  }) async {
    SharedPreferences.setMockInitialValues({DriveInterestCard.launchesKey: 5, ...stored});
    final prefs = await SharedPreferences.getInstance();
    final t = _Telemetry(prefs, on: telemetry);
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: DriveInterestCard(prefs: prefs, flags: _Flags(prefs, flag), telemetry: t),
        ),
      ),
    );
    await tester.pump();
    return (prefs, t);
  }

  final question = find.text('interest.title');

  testWidgets('hidden with the flag off, and nothing is counted', (tester) async {
    final (_, t) = await pump(tester, flag: false);
    expect(question, findsNothing);
    expect(t.events, isEmpty);
  });

  testWidgets('hidden when usage statistics are off', (tester) async {
    final (_, t) = await pump(tester, telemetry: false);
    expect(question, findsNothing);
    expect(t.events, isEmpty);
  });

  testWidgets('hidden once answered', (tester) async {
    final (_, t) = await pump(tester, stored: {DriveInterestCard.answerKey: 'no'});
    expect(question, findsNothing);
    expect(t.events, isEmpty);
  });

  testWidgets('shown once counts one view, however often it is rebuilt', (tester) async {
    final (prefs, t) = await pump(tester);
    expect(question, findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(t.events, ['view']);
    expect(prefs.getBool(DriveInterestCard.seenKey), isTrue);
  });

  testWidgets('a view already counted is not counted again', (tester) async {
    final (_, t) = await pump(tester, stored: {DriveInterestCard.seenKey: true});
    expect(question, findsOneWidget);
    expect(t.events, isEmpty);
  });

  testWidgets('an answer is counted, kept, and thanked', (tester) async {
    final (prefs, t) = await pump(tester);
    await tester.tap(find.text('interest.yes_paid'));
    await tester.pump();
    expect(t.events, ['view', 'yes_paid']);
    expect(prefs.getString(DriveInterestCard.answerKey), 'yes_paid');
    expect(question, findsNothing);
    expect(find.text('interest.thanks'), findsOneWidget);
  });

  testWidgets('closing counts a dismissal and shows nothing', (tester) async {
    final (prefs, t) = await pump(tester);
    await tester.tap(find.byType(ShadIconButton));
    await tester.pump();
    expect(t.events, ['view', 'dismiss']);
    expect(prefs.getString(DriveInterestCard.answerKey), 'dismiss');
    expect(question, findsNothing);
    expect(find.text('interest.thanks'), findsNothing);
  });
}
