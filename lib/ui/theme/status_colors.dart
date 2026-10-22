import 'package:flutter/material.dart';

// DESIGN.md section 3: status is always icon plus words, never color alone.
typedef StatusTone = ({Color fg, Color container, Color onContainer});
enum Status { ok, warning, danger, info }

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.ok, required this.warning, required this.danger, required this.info});
  final StatusTone ok, warning, danger, info;
  static const light = StatusColors(
    ok:      (fg: Color(0xFF1A6B3A), container: Color(0xFFD9EFE0), onContainer: Color(0xFF0E3D20)),
    warning: (fg: Color(0xFF8A5000), container: Color(0xFFFBEAC6), onContainer: Color(0xFF4A2C00)),
    danger:  (fg: Color(0xFFB42318), container: Color(0xFFFBE3DF), onContainer: Color(0xFF5A130B)),
    info:    (fg: Color(0xFF1D4E89), container: Color(0xFFD5E3F5), onContainer: Color(0xFF0D2A4C)));
  static const dark = StatusColors(
    ok:      (fg: Color(0xFF7DCB96), container: Color(0xFF163A23), onContainer: Color(0xFFC4EACF)),
    warning: (fg: Color(0xFFEDB65A), container: Color(0xFF3E2B07), onContainer: Color(0xFFF8E2B5)),
    danger:  (fg: Color(0xFFFFB3A8), container: Color(0xFF5E1A12), onContainer: Color(0xFFFCD9D3)),
    info:    (fg: Color(0xFFA9C7EF), container: Color(0xFF1F4573), onContainer: Color(0xFFD5E3F5)));
  StatusTone of(Status s) => switch (s) { Status.ok => ok, Status.warning => warning, Status.danger => danger, Status.info => info };
  @override StatusColors copyWith() => this;
  @override StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}
