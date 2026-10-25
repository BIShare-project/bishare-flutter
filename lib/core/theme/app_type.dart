import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

/// The BIShare type scale (redesign-plan.md "Type"): IBM Plex Sans in 400,
/// 500 and 600 only, numbers in tabular figures, no uppercase tracked labels.
/// The styles carry no colour; callers add one from `context.tokens`.
abstract final class AppType {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Tab titles ("Inbox", "Drive").
  static const title = TextStyle(
    fontSize: 27,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
    height: 1.15,
  );

  /// The device name in the Send header.
  static const deviceName = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.2,
  );

  /// Sheet titles and empty-state titles.
  static const sheetTitle = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
  );

  /// Pushed page bars.
  static const pageTitle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  /// Rows and buttons.
  static const row = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.3,
  );

  /// Emphasised rows and button labels.
  static const rowStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Paragraphs.
  static const body = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
  );

  /// Subtitles and metadata. Tabular, since metadata is mostly numbers.
  static const secondary = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w400,
    height: 1.35,
    fontFeatures: _tabular,
  );

  /// Section labels in sentence case.
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// Badges, legends, captions.
  static const small = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    fontFeatures: _tabular,
  );

  /// The bottom bar labels.
  static const nav = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  /// The room code.
  static const code = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w600,
    letterSpacing: 4.8,
    height: 1.15,
    fontFeatures: _tabular,
  );

  /// Numbers inside running text (sizes, percentages).
  static TextStyle tabular(TextStyle s) => s.copyWith(fontFeatures: _tabular);
}

/// Motion (redesign-plan.md "Motion and haptics"): transform and opacity
/// only. Reduced motion is read through `MediaQuery.disableAnimations` and
/// turns every duration to zero ([AppMotion.of]).
abstract final class AppMotion {
  static const select = Duration(milliseconds: 160);
  static const bar = Duration(milliseconds: 220);
  static const tab = Duration(milliseconds: 240);
  static const page = Duration(milliseconds: 280);
  static const sheet = Duration(milliseconds: 300);
  static const beam = Duration(milliseconds: 360);

  static const Curve standard = Cubic(0.3, 0.7, 0.2, 1);
  static const Curve enter = Cubic(0.2, 0.8, 0.2, 1);

  /// [d], or zero when the platform asks for reduced motion.
  static Duration of(bool disableAnimations, Duration d) =>
      disableAnimations ? Duration.zero : d;
}
