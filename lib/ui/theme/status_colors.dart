import 'package:flutter/material.dart';

// DESIGN.md section 3: status is always icon plus words, never color alone.
typedef StatusTone = ({Color fg, Color container, Color onContainer});
enum Status { ok, warning, danger, info }

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.ok, required this.warning, required this.danger, required this.info});
  final StatusTone ok, warning, danger, info;
  static const light = StatusColors(
    ok:      (fg: Color(0xFF2F6B3A), container: Color(0xFFDDEBDC), onContainer: Color(0xFF173A1F)),
    warning: (fg: Color(0xFF8A5300), container: Color(0xFFF4E3C3), onContainer: Color(0xFF452A00)),
    danger:  (fg: Color(0xFFA3321F), container: Color(0xFFF6DDD5), onContainer: Color(0xFF4F170D)),
    info:    (fg: Color(0xFF1D4E89), container: Color(0xFFDAE3EF), onContainer: Color(0xFF0F2E52)));
  static const dark = StatusColors(
    ok:      (fg: Color(0xFF8FC79A), container: Color(0xFF1F3524), onContainer: Color(0xFFCBE8D0)),
    warning: (fg: Color(0xFFE3AE5B), container: Color(0xFF3D2C0E), onContainer: Color(0xFFF5DDB0)),
    danger:  (fg: Color(0xFFF0A08C), container: Color(0xFF4A1F16), onContainer: Color(0xFFF8D3C8)),
    info:    (fg: Color(0xFF9DBDE6), container: Color(0xFF1D3F66), onContainer: Color(0xFFD9E3F0)));
  StatusTone of(Status s) => switch (s) { Status.ok => ok, Status.warning => warning, Status.danger => danger, Status.info => info };
  @override StatusColors copyWith() => this;
  @override StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}
