import 'package:flutter/material.dart';

// Values from DESIGN.md section 3: paper and ink by day, ink at night.
// Widgets read colorScheme, never these directly.
const lightScheme = ColorScheme(brightness: Brightness.light,
  primary: Color(0xFF1D4E89), onPrimary: Color(0xFFFFFFFF), primaryContainer: Color(0xFFDAE3EF), onPrimaryContainer: Color(0xFF0F2E52),
  secondary: Color(0xFF5C584F), onSecondary: Color(0xFFFFFFFF), secondaryContainer: Color(0xFFE2DACA), onSecondaryContainer: Color(0xFF1C1B19),
  tertiary: Color(0xFF5C584F), onTertiary: Color(0xFFFFFFFF), // unused; mirrors secondary
  error: Color(0xFFA3321F), onError: Color(0xFFFFFFFF), errorContainer: Color(0xFFF6DDD5), onErrorContainer: Color(0xFF4F170D),
  surface: Color(0xFFF5F2EA), onSurface: Color(0xFF1C1B19), onSurfaceVariant: Color(0xFF5C584F),
  surfaceContainerLowest: Color(0xFFFBF9F4), surfaceContainerLow: Color(0xFFEFEBE1), surfaceContainer: Color(0xFFEAE5D9),
  surfaceContainerHigh: Color(0xFFE4DED0), surfaceContainerHighest: Color(0xFFDED7C8),
  surfaceDim: Color(0xFFDED7C8), surfaceBright: Color(0xFFFBF9F4), outline: Color(0xFF857E70), outlineVariant: Color(0xFFD8D1C2),
  inverseSurface: Color(0xFF2E2C28), onInverseSurface: Color(0xFFF2EEE4), inversePrimary: Color(0xFF9DBDE6),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));

const darkScheme = ColorScheme(brightness: Brightness.dark,
  primary: Color(0xFF9DBDE6), onPrimary: Color(0xFF0F2E52), primaryContainer: Color(0xFF1D3F66), onPrimaryContainer: Color(0xFFD9E3F0),
  secondary: Color(0xFFADA696), onSecondary: Color(0xFF2E2C28), secondaryContainer: Color(0xFF3A352C), onSecondaryContainer: Color(0xFFEDE7DA),
  tertiary: Color(0xFFADA696), onTertiary: Color(0xFF2E2C28),
  error: Color(0xFFF0A08C), onError: Color(0xFF4F170D), errorContainer: Color(0xFF4A1F16), onErrorContainer: Color(0xFFF8D3C8),
  surface: Color(0xFF1A1814), onSurface: Color(0xFFEDE7DA), onSurfaceVariant: Color(0xFFADA696),
  surfaceContainerLowest: Color(0xFF141210), surfaceContainerLow: Color(0xFF201E19), surfaceContainer: Color(0xFF25221D),
  surfaceContainerHigh: Color(0xFF2C2923), surfaceContainerHighest: Color(0xFF34302A),
  surfaceDim: Color(0xFF1A1814), surfaceBright: Color(0xFF2C2923), outline: Color(0xFF857E70), outlineVariant: Color(0xFF423D35),
  inverseSurface: Color(0xFFEDE7DA), onInverseSurface: Color(0xFF2E2C28), inversePrimary: Color(0xFF1D4E89),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));
