import 'package:flutter/material.dart';

class AppStyles {
  // Colors
  static const MaterialColor primaryColor = Colors.blue;
  static const Color accentColor = Colors.blue;
  static const Color textPrimaryColor = Colors.black87;
  static const Color textSecondaryColor = Colors.black54;
  static const Color errorColor = Colors.red;

  // Text Styles
  static const TextStyle titleStyle = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    color: textPrimaryColor,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w500,
    color: textPrimaryColor,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 14.0,
    color: textPrimaryColor,
  );

  // Paddings & Margins
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;

  static const EdgeInsets contentPadding = EdgeInsets.all(paddingMedium);
  static const EdgeInsets cardPadding = EdgeInsets.all(paddingMedium);

  // Decorations
  static const BoxDecoration cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(8.0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black12,
        blurRadius: 4.0,
        offset: Offset(0, 2),
      ),
    ],
  );

  // Input Decorations
  static InputDecoration textFieldDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}