import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_tokens.dart';

/// BIShare theming, built on shadcn_ui with the BIShare tokens
/// ([AppTokens]). [accent] and [receive] are the accent names the settings
/// store (`blue`, `violet`, `rose`, `green`, ...).
class AppTheme {
  AppTheme._();

  /// App-wide typeface (bundled in assets/fonts), the same as bishare.app.
  static const fontFamily = 'IBM Plex Sans';

  static ShadThemeData light(String accent, {String receive = 'green'}) =>
      _data(AppTokens.of(Brightness.light, accent: accent, receive: receive));

  static ShadThemeData dark(String accent, {String receive = 'green'}) =>
      _data(AppTokens.of(Brightness.dark, accent: accent, receive: receive));

  static ShadThemeData _data(AppTokens t) => ShadThemeData(
    brightness: t.brightness,
    colorScheme: t.toShadColorScheme(),
    textTheme: ShadTextTheme(family: fontFamily),
  );

  /// The Material theme under the shadcn one: the font, the token extension
  /// and the plain background, so raw Material widgets match.
  static ThemeData material(
    ThemeData theme, {
    required String accent,
    required String receive,
  }) {
    final t = AppTokens.of(theme.brightness, accent: accent, receive: receive);
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: fontFamily),
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.line,
      splashFactory: InkRipple.splashFactory,
      extensions: [t],
    );
  }
}
