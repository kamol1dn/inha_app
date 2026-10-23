import 'package:flutter/material.dart';

// DESIGN.md section 4: the only text styles in the app. Fraunces carries the
// answers (room, titles, headers, course names, numerals); Public Sans the rest.
// Both are bundled in assets/fonts (tool/make_fonts.py), never fetched.
const _tnum = [FontFeature.tabularFigures()];
const _serif = 'Fraunces', _display = 'Fraunces Display', _sans = 'Public Sans';
// Neither face has Cyrillic or Hangul. A Cyrillic course name continues in the
// system serif (Noto Serif) rather than Roboto; the sans styles use the system default.
const _serifFallback = ['serif'];
const _even = TextLeadingDistribution.even;

TextStyle _s(String family, double size, double line, FontWeight weight,
        {FontStyle? style, double spacing = 0, bool tnum = false}) =>
    TextStyle(
      fontFamily: family,
      fontFamilyFallback: family == _sans ? null : _serifFallback,
      fontSize: size,
      height: line / size,
      fontWeight: weight,
      fontStyle: style,
      letterSpacing: spacing,
      leadingDistribution: _even,
      fontFeatures: tnum ? _tnum : null,
    );

final appTextTheme = TextTheme(
  displayMedium: _s(_display, 60, 64, FontWeight.w600, spacing: -1, tnum: true),
  headlineMedium: _s(_serif, 32, 38, FontWeight.w600, spacing: -0.5, tnum: true),
  headlineSmall: _s(_serif, 24, 30, FontWeight.w600),
  titleLarge: _s(_serif, 20, 26, FontWeight.w400, style: FontStyle.italic),
  titleMedium: _s(_serif, 19, 24, FontWeight.w600),
  titleSmall: _s(_sans, 16, 22, FontWeight.w600),
  bodyLarge: _s(_sans, 16, 24, FontWeight.w400),
  bodyMedium: _s(_sans, 14, 20, FontWeight.w400),
  bodySmall: _s(_sans, 12, 16, FontWeight.w400),
  labelLarge: _s(_sans, 15, 20, FontWeight.w600),
  labelMedium: _s(_sans, 12, 16, FontWeight.w500),
  labelSmall: _s(_sans, 11, 16, FontWeight.w500),
  // Never used; set so nothing falls back to the M3 Roboto metrics.
  displayLarge: _s(_sans, 57, 64, FontWeight.w400),
  displaySmall: _s(_sans, 36, 44, FontWeight.w400),
  headlineLarge: _s(_sans, 32, 40, FontWeight.w400),
);

extension Numerals on TextTheme {
  /// Start times on the rails and Deadlines; the count beside a tally.
  TextStyle get numeral => titleMedium!.copyWith(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w400, fontFeatures: _tnum);

  /// End times on the rails.
  TextStyle get numeralSmall => numeral.copyWith(fontSize: 14, height: 20 / 14);
}

extension Tnum on TextStyle { TextStyle get tnum => copyWith(fontFeatures: _tnum); }
