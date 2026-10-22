import '../../models/models.dart';

/// INS / ITIS (ins.inha.uz), an ASP.NET WebForms frameset. See docs/ENDPOINTS.md.
abstract class InsApi {
  /// Throws [LoginRequired] if INS rejects the saved credentials.
  Future<void> ensureLoggedIn();

  /// All course results plus GPA and credits.
  Future<GradeReport> grades();
}
