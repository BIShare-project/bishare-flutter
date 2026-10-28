import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// BIShare theming: a Material theme filled from the BIShare tokens
/// ([AppTokens], also attached as a theme extension, read through
/// `context.tokens`). [accent] and [receive] are the accent names the
/// settings store (`blue`, `violet`, `rose`, `green`, ...).
class AppTheme {
  AppTheme._();

  /// App-wide typeface (bundled in assets/fonts), the same as bishare.app.
  static const fontFamily = 'IBM Plex Sans';

  static ThemeData light(String accent, {String receive = 'green'}) =>
      _data(AppTokens.of(Brightness.light, accent: accent, receive: receive));

  static ThemeData dark(String accent, {String receive = 'green'}) =>
      _data(AppTokens.of(Brightness.dark, accent: accent, receive: receive));

  static ThemeData _data(AppTokens t) {
    final base = ThemeData(
      brightness: t.brightness,
      fontFamily: fontFamily,
      colorScheme: ColorScheme(
        brightness: t.brightness,
        primary: t.accent,
        onPrimary: AppPalette.onColor(t.accent),
        secondary: t.receive,
        onSecondary: t.onReceive,
        error: t.danger,
        onError: t.onDanger,
        surface: t.surface,
        onSurface: t.text,
        onSurfaceVariant: t.text2,
        outline: t.line,
        outlineVariant: t.line,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.line,
      splashFactory: InkRipple.splashFactory,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accentSoft,
        selectionHandleColor: t.accent,
      ),
      extensions: [t],
    );
  }
}
