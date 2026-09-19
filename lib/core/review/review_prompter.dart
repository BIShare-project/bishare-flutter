import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks for a store rating at the one moment it is fair to: right after a
/// transfer has worked, for someone who has seen it work before.
///
/// The dialog is the operating system's own (App Store / Google Play), so there
/// is no copy of ours in it, and the OS applies its own quota on top of the
/// rules here. On a build that did not come from a store — a sideloaded APK,
/// the notarized DMG — the request quietly does nothing.
class ReviewPrompter {
  ReviewPrompter(
    this._prefs, {
    InAppReview? review,
    @visibleForTesting bool? supported,
    @visibleForTesting Duration quiet = const Duration(seconds: 4),
  }) : _review = review ?? InAppReview.instance,
       _supported = supported ?? _storePlatform,
       _quiet = quiet;

  final SharedPreferences _prefs;
  final InAppReview _review;
  final bool _supported;

  /// A receive reports every FILE, so fifty photos arrive as fifty successes.
  /// Successes this close together are one transfer, and the ask waits for the
  /// run to go quiet so it never lands in the middle of one.
  final Duration _quiet;

  static const _countKey = 'reviewSuccesses';
  static const _asksKey = 'reviewAsks';
  static const _lastAskKey = 'reviewLastAskAt';

  /// Successful transfers before the first ask, and before the second.
  static const firstAskAfter = 3;
  static const secondAskAfter = 15;

  /// The second ask also waits this long after the first.
  static const secondAskGap = Duration(days: 120);

  Timer? _settle;

  /// Platforms whose store has an in-app rating dialog.
  static bool get _storePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Whether to ask now. At most twice in the life of an install: once the app
  /// has plainly worked ([firstAskAfter] transfers), and once more much later
  /// for someone who kept using it. Never a third time — the person who has
  /// dismissed it twice has answered.
  @visibleForTesting
  static bool shouldAsk({
    required int successes,
    required int asks,
    required int? lastAskMs,
    required DateTime now,
  }) {
    if (asks == 0) return successes >= firstAskAfter;
    if (asks == 1) {
      if (successes < secondAskAfter || lastAskMs == null) return false;
      final since = now.millisecondsSinceEpoch - lastAskMs;
      return since >= secondAskGap.inMilliseconds;
    }
    return false;
  }

  /// Call when a transfer succeeds, in either direction. Cheap and safe to call
  /// per file; nothing happens until the run of successes has gone quiet.
  void noteSuccess() {
    if (!_supported) return;
    _settle?.cancel();
    _settle = Timer(_quiet, () => unawaited(_onTransferSettled()));
  }

  Future<void> _onTransferSettled() async {
    try {
      final successes = (_prefs.getInt(_countKey) ?? 0) + 1;
      await _prefs.setInt(_countKey, successes);
      final asks = _prefs.getInt(_asksKey) ?? 0;
      final due = shouldAsk(
        successes: successes,
        asks: asks,
        lastAskMs: _prefs.getInt(_lastAskKey),
        now: DateTime.now(),
      );
      if (!due || !await _review.isAvailable()) return;
      // Recorded before the request: the OS never says whether it showed the
      // dialog, and an ask that may have been seen must count as one.
      await _prefs.setInt(_asksKey, asks + 1);
      await _prefs.setInt(_lastAskKey, DateTime.now().millisecondsSinceEpoch);
      await _review.requestReview();
    } on Object {
      // A rating prompt must never be the reason anything else fails.
    }
  }

  void dispose() => _settle?.cancel();
}
