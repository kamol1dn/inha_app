import 'package:flutter/material.dart';

// DESIGN.md section 4: the only nine text styles in the app.
const _tnum = [FontFeature.tabularFigures()];
const appTextTheme = TextTheme(
  headlineMedium: TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w500, fontFeatures: _tnum),
  titleLarge: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w500),
  titleMedium: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w500),
  titleSmall: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700),
  bodyLarge: TextStyle(fontSize: 16, height: 24 / 16), bodyMedium: TextStyle(fontSize: 14, height: 20 / 14),
  bodySmall: TextStyle(fontSize: 12, height: 16 / 12),
  labelLarge: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500),
  labelMedium: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500));
extension Tnum on TextStyle { TextStyle get tnum => copyWith(fontFeatures: _tnum); }
