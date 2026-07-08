import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// BIShare theming, built on shadcn_ui. The [accent] is a shadcn color-scheme
/// name (`blue`, `green`, `violet`, `rose`, `orange`, `red`, `yellow`, `slate`).
class AppTheme {
  AppTheme._();

  /// App-wide typeface (bundled in assets/fonts).
  static const fontFamily = 'IBM Plex Sans';

  static ShadThemeData light(String accent) => ShadThemeData(
    brightness: Brightness.light,
    colorScheme: ShadColorScheme.fromName(accent, brightness: Brightness.light),
    textTheme: ShadTextTheme(family: fontFamily),
  );

  static ShadThemeData dark(String accent) => ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: ShadColorScheme.fromName(accent, brightness: Brightness.dark),
    textTheme: ShadTextTheme(family: fontFamily),
  );
}
