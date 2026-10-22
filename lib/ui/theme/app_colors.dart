import 'package:flutter/material.dart';

// Values from DESIGN.md section 3. Widgets read colorScheme, never these directly.
const lightScheme = ColorScheme(brightness: Brightness.light,
  primary: Color(0xFF1D4E89), onPrimary: Color(0xFFFFFFFF), primaryContainer: Color(0xFFD5E3F5), onPrimaryContainer: Color(0xFF0D2A4C),
  secondary: Color(0xFF4A5868), onSecondary: Color(0xFFFFFFFF), secondaryContainer: Color(0xFFDCE3EB), onSecondaryContainer: Color(0xFF1D2833),
  tertiary: Color(0xFF4A5868), onTertiary: Color(0xFFFFFFFF), // unused; mirrors secondary
  error: Color(0xFFB42318), onError: Color(0xFFFFFFFF), errorContainer: Color(0xFFFBE3DF), onErrorContainer: Color(0xFF5A130B),
  surface: Color(0xFFF7F8FA), onSurface: Color(0xFF191C20), onSurfaceVariant: Color(0xFF4A525C),
  surfaceContainerLowest: Color(0xFFFDFDFE), surfaceContainerLow: Color(0xFFF1F3F5), surfaceContainer: Color(0xFFEBEEF1),
  surfaceContainerHigh: Color(0xFFE5E8EC), surfaceContainerHighest: Color(0xFFDFE2E6),
  surfaceDim: Color(0xFFD7DADE), surfaceBright: Color(0xFFF7F8FA), outline: Color(0xFF737B85), outlineVariant: Color(0xFFD8DCE1),
  inverseSurface: Color(0xFF2D3136), onInverseSurface: Color(0xFFEEF0F3), inversePrimary: Color(0xFFA9C7EF),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));

const darkScheme = ColorScheme(brightness: Brightness.dark,
  primary: Color(0xFFA9C7EF), onPrimary: Color(0xFF0D2A4C), primaryContainer: Color(0xFF1F4573), onPrimaryContainer: Color(0xFFD5E3F5),
  secondary: Color(0xFFB5C0CC), onSecondary: Color(0xFF1F2A35), secondaryContainer: Color(0xFF353F4A), onSecondaryContainer: Color(0xFFDCE3EB),
  tertiary: Color(0xFFB5C0CC), onTertiary: Color(0xFF1F2A35),
  error: Color(0xFFFFB3A8), onError: Color(0xFF5A130B), errorContainer: Color(0xFF5E1A12), onErrorContainer: Color(0xFFFCD9D3),
  surface: Color(0xFF121418), onSurface: Color(0xFFE2E4E8), onSurfaceVariant: Color(0xFFA8AFB8),
  surfaceContainerLowest: Color(0xFF0C0E11), surfaceContainerLow: Color(0xFF181B1F), surfaceContainer: Color(0xFF1C1F24),
  surfaceContainerHigh: Color(0xFF24282D), surfaceContainerHighest: Color(0xFF2C3036),
  surfaceDim: Color(0xFF121418), surfaceBright: Color(0xFF383D44), outline: Color(0xFF878E98), outlineVariant: Color(0xFF353A41),
  inverseSurface: Color(0xFFE2E4E8), onInverseSurface: Color(0xFF2D3136), inversePrimary: Color(0xFF1D4E89),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));
