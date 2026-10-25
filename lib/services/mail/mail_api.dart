import '../../models/models.dart';

/// University mail through Exchange Web Services (mail.inha.uz/EWS/Exchange.asmx)
/// with Basic auth. See docs/ENDPOINTS.md.
abstract class MailApi {
  /// One page of [folder], newest first. Throws [LoginRequired] on 401.
  Future<List<MailHeader>> folder(MailFolder folder, {int limit = 30, int offset = 0});

  /// One message with its plain-text body, recipients and attachment list.
  /// Does not change its read state.
  Future<MailMessage> message(String id);

  /// Sets the message's read flag (no read receipt is sent).
  Future<void> markRead(String id, {bool read = true});

  /// The inbox's unread count.
  Future<int> unreadCount();

  /// Unread and total counts of every [MailFolder] the mailbox has.
  Future<Map<MailFolder, MailFolderCount>> folderCounts();

  /// Sends [m]; a copy goes to Sent. A saved draft is sent as it is, after
  /// writing what changed.
  Future<void> send(OutgoingMail m);

  /// Saves [m] to Drafts, or writes the changes to a saved draft.
  Future<void> saveDraft(OutgoingMail m);

  /// Moves a message to [to]; deleting is a move to [MailFolder.deleted].
  /// Returns its id in the new folder, or null when Exchange didn't say.
  Future<String?> move(String id, MailFolder to);

  /// People and lists whose name or address starts with [query].
  Future<List<MailAddress>> lookup(String query);
}
