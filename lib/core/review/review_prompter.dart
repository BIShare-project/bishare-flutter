import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:get_it/get_it.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks for a store rating the moment a transfer has worked: right after the
/// first one, then again for people who keep using the app.
///
/// On iOS, macOS and Android the dialog is the operating system's own (App
/// Store / Google Play), so there is no copy of ours in it, and the OS applies
/// its own quota on top of the rules here (Apple: at most three a year). Apple
/// (5.6.1) and Google forbid a home-made rating prompt and asking whether
/// someone likes the app first, so those platforms only ever get the system
/// dialog. The Microsoft Store has no such dialog for this plugin; a Store
/// install on Windows gets a short banner instead ([onWindowsAsk]) with a
/// button to the Store's rating page. On a build that did not come from a
/// store (a sideloaded APK, the notarized DMG, the Windows ZIP) nothing asks.
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

  /// Successful transfers before each ask: right after the first one that
  /// works, again for someone who kept using it, and a last time for a
  /// regular.
  static const askAfter = [1, 8, 20];

  /// Each later ask also waits this long after the one before.
  static const askGaps = [Duration(days: 30), Duration(days: 90)];

  /// Shows the Windows banner (set by the shell, which owns a context).
  /// Returns whether it was shown.
  bool Function()? onWindowsAsk;

  Timer? _settle;

  /// Platforms whose store has an in-app rating dialog, plus a Windows
  /// install that came from the Microsoft Store (an MSIX lives under
  /// WindowsApps; the ZIP, Scoop and winget builds do not).
  static bool get _storePlatform =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          (Platform.isWindows &&
              Platform.resolvedExecutable.contains(r'\WindowsApps\')));

  /// Whether to ask now. At most [askAfter].length times in the life of an
  /// install, each needing more use and, after the first, time since the one
  /// before. Never a fourth: three dismissals are an answer.
  @visibleForTesting
  static bool shouldAsk({
    required int successes,
    required int asks,
    required int? lastAskMs,
    required DateTime now,
  }) {
    if (asks >= askAfter.length || successes < askAfter[asks]) return false;
    if (asks == 0) return true;
    if (lastAskMs == null) return false;
    final since = now.millisecondsSinceEpoch - lastAskMs;
    return since >= askGaps[asks - 1].inMilliseconds;
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
      if (!due) return;
      if (!kIsWeb && Platform.isWindows) {
        if (onWindowsAsk?.call() ?? false) await _recordAsk(asks);
        return;
      }
      if (!await _review.isAvailable()) return;
      // Recorded before the request: the OS never says whether it showed the
      // dialog, and an ask that may have been seen must count as one.
      await _recordAsk(asks);
      await _review.requestReview();
    } on Object {
      // A rating prompt must never be the reason anything else fails.
    }
  }

  Future<void> _recordAsk(int asks) async {
    await _prefs.setInt(_asksKey, asks + 1);
    await _prefs.setInt(_lastAskKey, DateTime.now().millisecondsSinceEpoch);
  }

  void dispose() => _settle?.cancel();
}

/// [ReviewPrompter.noteSuccess] for the flows that are not handed a prompter
/// (Secure Link, rooms, Nearby, the browser bridge, link downloads).
void noteTransferSuccess() {
  final getIt = GetIt.instance;
  if (getIt.isRegistered<ReviewPrompter>()) getIt<ReviewPrompter>().noteSuccess();
}
