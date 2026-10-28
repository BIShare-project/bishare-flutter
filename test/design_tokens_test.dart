// redesign-plan.md task 1.1: every text colour the tokens hand out reads at
// WCAG AA (4.5:1) on the surfaces it is drawn on, in both themes and with
// every accent the settings offer.
import 'package:bishare/core/theme/app_palette.dart';
import 'package:bishare/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _aa = 4.5;

void _expectReads(Color fg, Color bg, String what) {
  final r = AppPalette.contrast(fg, bg);
  expect(
    r,
    greaterThanOrEqualTo(_aa),
    reason: '$what is ${r.toStringAsFixed(2)}:1',
  );
}

void main() {
  for (final b in Brightness.values) {
    group('$b', () {
      final t = AppTokens.of(b);

      test('neutral text on every surface', () {
        for (final (name, surface) in [
          ('bg', t.bg),
          ('surface', t.surface),
          ('raised', t.raised),
          ('sunken', t.sunken),
        ]) {
          _expectReads(t.text, surface, 'text on $name');
          _expectReads(t.text2, surface, 'text2 on $name');
          _expectReads(t.text3, surface, 'text3 on $name');
          _expectReads(t.danger, surface, 'danger on $name');
        }
        for (final (name, surface) in [('bg', t.bg), ('surface', t.surface)]) {
          _expectReads(t.ok, surface, 'ok on $name');
          _expectReads(t.warn, surface, 'warn on $name');
        }
        _expectReads(t.onDanger, t.danger, 'onDanger on danger');
      });

      for (final name in AppPalette.accents.keys) {
        test('accent $name', () {
          final a = AppTokens.of(b, accent: name, receive: name);
          for (final (sn, surface) in [
            ('bg', a.bg),
            ('surface', a.surface),
            ('raised', a.raised),
          ]) {
            _expectReads(a.accent, surface, '$name accent on $sn');
            _expectReads(a.receive, surface, '$name receive on $sn');
          }
          _expectReads(a.onAccent, a.accentStrong, 'onAccent on $name fill');
          _expectReads(a.onReceive, a.receiveStrong, 'onReceive on $name fill');
          _expectReads(AppPalette.onColor(a.accent), a.accent, 'theme primary pair');
          _expectReads(a.accent, a.bg, 'theme primary as text');
        });
      }

      test('white on the brand gradient, at 11 stops', () {
        final g = t.brandSurface as LinearGradient;
        for (var i = 0; i <= 10; i++) {
          final c = Color.lerp(g.colors.first, g.colors.last, i / 10)!;
          _expectReads(const Color(0xFFFFFFFF), c, 'white at stop $i');
        }
      });
    });
  }

  test('an unknown accent falls back to blue', () {
    expect(
      AppTokens.of(Brightness.light, accent: 'nope').accent,
      AppTokens.of(Brightness.light).accent,
    );
  });
}
