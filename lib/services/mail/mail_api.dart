import '../../models/models.dart';

/// University mail through Exchange Web Services (mail.inha.uz/EWS/Exchange.asmx)
/// with Basic auth. See docs/ENDPOINTS.md.
abstract class MailApi {
  /// Newest first. Throws [LoginRequired] on 401.
  Future<List<MailHeader>> inbox({int limit = 30, int offset = 0});

  /// One message with its plain-text body and attachment list. Does not
  /// change its read state.
  Future<MailMessage> message(String id);

  /// Sets the message's read flag (no read receipt is sent).
  Future<void> markRead(String id, {bool read = true});

  Future<int> unreadCount();
}
