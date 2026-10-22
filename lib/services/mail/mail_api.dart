import '../../models/models.dart';

/// University mail through Exchange Web Services (mail.inha.uz/EWS/Exchange.asmx)
/// with Basic auth. See docs/ENDPOINTS.md.
abstract class MailApi {
  /// Newest first. Throws [LoginRequired] on 401.
  Future<List<MailHeader>> inbox({int limit = 30, int offset = 0});

  /// Plain-text body of one message.
  Future<String> body(String id);

  Future<int> unreadCount();
}
