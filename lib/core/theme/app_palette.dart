import 'package:flutter/painting.dart';

/// One selectable accent: the colour on light surfaces, the colour for text
/// and thin lines on dark surfaces, and the fill under text on dark surfaces.
/// Every value keeps 4.5:1 against the surfaces it is drawn on
/// (test/design_tokens_test.dart).
typedef AccentSpec = ({Color light, Color darkText, Color darkFill});

/// The BIShare palette (redesign-plan.md "Colour tokens"). The neutrals are
/// graphite and paper so that the user's own photos carry the colour; one
/// accent marks selection, the main action and progress.
abstract final class AppPalette {
  // Light neutrals.
  static const lightBg = Color(0xFFF6F7F9);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightRaised = Color(0xFFFFFFFF);
  static const lightSunken = Color(0xFFEDEFF2);
  static const lightLine = Color(0xFFE1E4E9);
  static const lightText = Color(0xFF0F1216);
  static const lightText2 = Color(0xFF545D69);
  static const lightText3 = Color(0xFF646C78);
  static const lightOk = Color(0xFF17804A);
  static const lightDanger = Color(0xFFC42B2B);
  static const lightWarn = Color(0xFF9A6200);

  // Dark neutrals.
  static const darkBg = Color(0xFF0C0E11);
  static const darkSurface = Color(0xFF15181C);
  static const darkRaised = Color(0xFF1C1F25);
  static const darkSunken = Color(0xFF181B20);
  static const darkLine = Color(0xFF262A31);
  static const darkText = Color(0xFFF1F3F5);
  static const darkText2 = Color(0xFFA0A8B3);
  static const darkText3 = Color(0xFF8A929D);
  static const darkOk = Color(0xFF3FB97A);
  static const darkDanger = Color(0xFFF26D6D);
  static const darkWarn = Color(0xFFE0A83A);

  /// Ink for text on a light fill (a dark accent fill that white cannot read
  /// on, such as yellow in the dark theme).
  static const ink = Color(0xFF0C0E11);

  /// The BIShare gradient, as on bishare.app and the app icon. The deep stops
  /// carry white text (at least 5.3:1 across the whole surface); the bright
  /// stops are for thin lines only (the radar beam, progress).
  static const brandDeep = [Color(0xFF1D4ED8), Color(0xFF0E7490)];
  static const brandBright = [Color(0xFF3B82F6), Color(0xFF22D3EE)];

  /// The accents the settings offer, by the shadcn scheme names the app has
  /// always stored (`Settings.accent`, `Settings.receiveAccent`).
  static const Map<String, AccentSpec> accents = {
    'blue': (
      light: Color(0xFF0060DF),
      darkText: Color(0xFF4A8CF7),
      darkFill: Color(0xFF2563EB),
    ),
    'violet': (
      light: Color(0xFF7C3AED),
      darkText: Color(0xFFA78BFA),
      darkFill: Color(0xFF7C3AED),
    ),
    'rose': (
      light: Color(0xFFBE123C),
      darkText: Color(0xFFFB7185),
      darkFill: Color(0xFFBE123C),
    ),
    'green': (
      light: Color(0xFF15803D),
      darkText: Color(0xFF3FB97A),
      darkFill: Color(0xFF15803D),
    ),
    'orange': (
      light: Color(0xFFC2410C),
      darkText: Color(0xFFFB923C),
      darkFill: Color(0xFFC2410C),
    ),
    'red': (
      light: Color(0xFFB91C1C),
      darkText: Color(0xFFF87171),
      darkFill: Color(0xFFB91C1C),
    ),
    'yellow': (
      light: Color(0xFFA16207),
      darkText: Color(0xFFFACC15),
      darkFill: Color(0xFFA16207),
    ),
    'slate': (
      light: Color(0xFF475569),
      darkText: Color(0xFF94A3B8),
      darkFill: Color(0xFF475569),
    ),
    'gray': (
      light: Color(0xFF4B5563),
      darkText: Color(0xFF9CA3AF),
      darkFill: Color(0xFF4B5563),
    ),
    'zinc': (
      light: Color(0xFF52525B),
      darkText: Color(0xFFA1A1AA),
      darkFill: Color(0xFF52525B),
    ),
    'neutral': (
      light: Color(0xFF525252),
      darkText: Color(0xFFA3A3A3),
      darkFill: Color(0xFF525252),
    ),
    'stone': (
      light: Color(0xFF57534E),
      darkText: Color(0xFFA8A29E),
      darkFill: Color(0xFF57534E),
    ),
  };

  static AccentSpec accent(String name) => accents[name] ?? accents['blue']!;

  /// WCAG contrast ratio of two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// White on [fill] when white reads at 4.5:1, otherwise [ink].
  static Color onColor(Color fill) =>
      contrast(const Color(0xFFFFFFFF), fill) >= 4.5
      ? const Color(0xFFFFFFFF)
      : ink;
}
