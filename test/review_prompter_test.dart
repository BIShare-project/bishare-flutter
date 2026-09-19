import 'package:bishare/core/review/review_prompter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeReview implements InAppReview {
  _FakeReview({this.available = true});
  final bool available;
  int requests = 0;

  /// What the prompter had already saved when the dialog was requested.
  int? asksSavedAtRequest;
  SharedPreferences? prefs;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    requests++;
    asksSavedAtRequest = prefs?.getInt('reviewAsks');
  }

  @override
  Future<void> openStoreListing({String? appStoreId, String? microsoftStoreId}) async {}
}

const _quiet = Duration(milliseconds: 20);
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  final now = DateTime.utc(2026, 9, 19);
  int daysAgo(int d) => now.subtract(Duration(days: d)).millisecondsSinceEpoch;

  group('shouldAsk', () {
    test('not before the third successful transfer', () {
      expect(ReviewPrompter.shouldAsk(successes: 2, asks: 0, lastAskMs: null, now: now), isFalse);
      expect(ReviewPrompter.shouldAsk(successes: 3, asks: 0, lastAskMs: null, now: now), isTrue);
    });

    test('the second ask needs both more use and 120 days', () {
      expect(ReviewPrompter.shouldAsk(successes: 40, asks: 1, lastAskMs: daysAgo(119), now: now), isFalse);
      expect(ReviewPrompter.shouldAsk(successes: 14, asks: 1, lastAskMs: daysAgo(400), now: now), isFalse);
      expect(ReviewPrompter.shouldAsk(successes: 15, asks: 1, lastAskMs: daysAgo(120), now: now), isTrue);
    });

    test('never a third time', () {
      expect(ReviewPrompter.shouldAsk(successes: 9999, asks: 2, lastAskMs: daysAgo(900), now: now), isFalse);
    });
  });

  group('noteSuccess', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('fifty files in one receive count as one transfer', () async {
      final review = _FakeReview();
      final p = ReviewPrompter(prefs, review: review, supported: true, quiet: _quiet);
      for (var i = 0; i < 50; i++) {
        p.noteSuccess();
      }
      await _settle();
      expect(prefs.getInt('reviewSuccesses'), 1);
      expect(review.requests, 0);
    });

    test('asks once, after the third transfer has gone quiet', () async {
      final review = _FakeReview()..prefs = prefs;
      final p = ReviewPrompter(prefs, review: review, supported: true, quiet: _quiet);
      for (var t = 0; t < 5; t++) {
        p.noteSuccess();
        await _settle();
      }
      expect(prefs.getInt('reviewSuccesses'), 5);
      expect(review.requests, 1);
      // Saved BEFORE the dialog: the OS never reports whether it was shown.
      expect(review.asksSavedAtRequest, 1);
    });

    test('an unavailable store is not counted as an ask', () async {
      final review = _FakeReview(available: false);
      final p = ReviewPrompter(prefs, review: review, supported: true, quiet: _quiet);
      for (var t = 0; t < 4; t++) {
        p.noteSuccess();
        await _settle();
      }
      expect(review.requests, 0);
      expect(prefs.getInt('reviewAsks'), isNull);
    });

    test('does nothing on a platform without a store dialog', () async {
      final review = _FakeReview();
      final p = ReviewPrompter(prefs, review: review, supported: false, quiet: _quiet);
      for (var t = 0; t < 4; t++) {
        p.noteSuccess();
        await _settle();
      }
      expect(prefs.getInt('reviewSuccesses'), isNull);
      expect(review.requests, 0);
    });
  });
}
