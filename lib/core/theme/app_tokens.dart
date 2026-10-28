import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'app_palette.dart';

/// The BIShare design tokens for one brightness and one pair of accents.
/// Read them with `context.tokens`. They ride on the Material theme as a
/// [ThemeExtension] (see `BIShareApp`); a tree without that extension (a
/// widget test that builds its own ShadApp) gets the defaults for its
/// brightness, so nothing ever reads null.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.raised,
    required this.sunken,
    required this.line,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentStrong,
    required this.onAccent,
    required this.accentSoft,
    required this.receive,
    required this.receiveStrong,
    required this.onReceive,
    required this.receiveSoft,
    required this.ok,
    required this.danger,
    required this.onDanger,
    required this.warn,
    required this.scrim,
    required this.brandSurface,
    required this.brandLine,
  });

  factory AppTokens.of(
    Brightness brightness, {
    String accent = 'blue',
    String receive = 'green',
  }) {
    final dark = brightness == Brightness.dark;
    final a = AppPalette.accent(accent), r = AppPalette.accent(receive);
    final accentText = dark ? a.darkText : a.light;
    final accentFill = dark ? a.darkFill : a.light;
    final receiveText = dark ? r.darkText : r.light;
    final receiveFill = dark ? r.darkFill : r.light;
    final danger = dark ? AppPalette.darkDanger : AppPalette.lightDanger;
    // The brand gradient stands for "sending" only while the send accent is
    // blue; another accent replaces it with its own colour.
    final blue = accent == 'blue' || !AppPalette.accents.containsKey(accent);
    return AppTokens(
      brightness: brightness,
      bg: dark ? AppPalette.darkBg : AppPalette.lightBg,
      surface: dark ? AppPalette.darkSurface : AppPalette.lightSurface,
      raised: dark ? AppPalette.darkRaised : AppPalette.lightRaised,
      sunken: dark ? AppPalette.darkSunken : AppPalette.lightSunken,
      line: dark ? AppPalette.darkLine : AppPalette.lightLine,
      text: dark ? AppPalette.darkText : AppPalette.lightText,
      text2: dark ? AppPalette.darkText2 : AppPalette.lightText2,
      text3: dark ? AppPalette.darkText3 : AppPalette.lightText3,
      accent: accentText,
      accentStrong: accentFill,
      onAccent: AppPalette.onColor(accentFill),
      accentSoft: accentText.withValues(alpha: dark ? 0.16 : 0.10),
      receive: receiveText,
      receiveStrong: receiveFill,
      onReceive: AppPalette.onColor(receiveFill),
      receiveSoft: receiveText.withValues(alpha: dark ? 0.16 : 0.10),
      ok: dark ? AppPalette.darkOk : AppPalette.lightOk,
      danger: danger,
      onDanger: AppPalette.onColor(danger),
      warn: dark ? AppPalette.darkWarn : AppPalette.lightWarn,
      scrim: dark
          ? const Color(0x8C000000)
          : AppPalette.lightText.withValues(alpha: 0.38),
      brandSurface: LinearGradient(
        begin: const Alignment(-1, -0.18),
        end: const Alignment(1, 0.18),
        colors: blue ? AppPalette.brandDeep : [accentFill, accentFill],
      ),
      brandLine: LinearGradient(
        colors: blue ? AppPalette.brandBright : [accentText, accentText],
      ),
    );
  }

  final Brightness brightness;

  /// Screen background.
  final Color bg;

  /// Cards and rows that sit on a card.
  final Color surface;

  /// Sheets and floating cards.
  final Color raised;

  /// Inputs, segmented tracks, tile placeholders.
  final Color sunken;

  /// Hairlines and borders.
  final Color line;

  final Color text;
  final Color text2;
  final Color text3;

  /// Accent for text and thin graphics (readable on bg, surface, raised).
  final Color accent;

  /// Accent fill under [onAccent] text (filled buttons, selection badges).
  final Color accentStrong;
  final Color onAccent;

  /// Backing of a selected tile or row.
  final Color accentSoft;

  /// The receive accent: the incoming sheet and the receive card only.
  final Color receive;
  final Color receiveStrong;
  final Color onReceive;
  final Color receiveSoft;

  final Color ok;
  final Color danger;
  final Color onDanger;
  final Color warn;

  /// Behind sheets.
  final Color scrim;

  /// "Sending": the selection bar, the action bar. Carries white text.
  final Gradient brandSurface;

  /// "Data is moving": the radar beam, progress rings and lines.
  final Gradient brandLine;

  bool get isDark => brightness == Brightness.dark;

  /// A sheet's own background, a step below its cards ([sheetCard]), so the
  /// grouped rows read as cards (iOS inset grouped).
  Color get sheetBg => isDark ? surface : bg;

  /// The cards in a sheet: rows, facts, the quick actions.
  Color get sheetCard =>
      isDark ? Color.lerp(raised, const Color(0xFFFFFFFF), 0.035)! : raised;

  @override
  AppTokens copyWith() => this;

  /// The same tokens with the receive accent in the accent's place, so
  /// buttons, switches and focus rings inside a receiving surface (the offer
  /// sheet, the Terima code) take the receive colour with no extra params.
  AppTokens get receiving => AppTokens(
    brightness: brightness,
    bg: bg,
    surface: surface,
    raised: raised,
    sunken: sunken,
    line: line,
    text: text,
    text2: text2,
    text3: text3,
    accent: receive,
    accentStrong: receiveStrong,
    onAccent: onReceive,
    accentSoft: receiveSoft,
    receive: receive,
    receiveStrong: receiveStrong,
    onReceive: onReceive,
    receiveSoft: receiveSoft,
    ok: ok,
    danger: danger,
    onDanger: onDanger,
    warn: warn,
    scrim: scrim,
    brandSurface: brandSurface,
    brandLine: brandLine,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      sunken: c(sunken, other.sunken),
      line: c(line, other.line),
      text: c(text, other.text),
      text2: c(text2, other.text2),
      text3: c(text3, other.text3),
      accent: c(accent, other.accent),
      accentStrong: c(accentStrong, other.accentStrong),
      onAccent: c(onAccent, other.onAccent),
      accentSoft: c(accentSoft, other.accentSoft),
      receive: c(receive, other.receive),
      receiveStrong: c(receiveStrong, other.receiveStrong),
      onReceive: c(onReceive, other.onReceive),
      receiveSoft: c(receiveSoft, other.receiveSoft),
      ok: c(ok, other.ok),
      danger: c(danger, other.danger),
      onDanger: c(onDanger, other.onDanger),
      warn: c(warn, other.warn),
      scrim: c(scrim, other.scrim),
      brandSurface: t < 0.5 ? brandSurface : other.brandSurface,
      brandLine: t < 0.5 ? brandLine : other.brandLine,
    );
  }

  /// The shadcn colour scheme the existing widgets read (117 files use
  /// `ShadTheme`), filled from these tokens so every screen takes the new
  /// palette before it is rebuilt.
  ///
  /// `primary` is the text-safe accent, so `cs.primary` used as a link colour
  /// stays readable; filled buttons of the new kit use [accentStrong].
  ShadColorScheme toShadColorScheme() => ShadColorScheme(
    background: bg,
    foreground: text,
    card: surface,
    cardForeground: text,
    popover: raised,
    popoverForeground: text,
    primary: accent,
    primaryForeground: AppPalette.onColor(accent),
    secondary: sunken,
    secondaryForeground: text,
    muted: sunken,
    mutedForeground: text2,
    accent: sunken,
    accentForeground: text,
    destructive: danger,
    destructiveForeground: onDanger,
    border: line,
    input: line,
    ring: accent,
    selection: accentSoft,
  );
}

/// Puts [AppTokens.receiving] over [child]: the receive accent becomes the
/// accent below it.
class ReceiveTone extends StatelessWidget {
  const ReceiveTone({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.tokens;
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((e) => e is! AppTokens),
          t.receiving,
        ],
        colorScheme: theme.colorScheme.copyWith(primary: t.receive),
      ),
      child: child,
    );
  }
}

extension AppTokensContext on BuildContext {
  /// The design tokens of the nearest theme.
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ??
      AppTokens.of(ShadTheme.of(this).brightness);
}
