/// Exchange Web Services SOAP: request envelopes and response readers for
/// the mail client (docs/ENDPOINTS.md, Mail). Pure functions, no I/O.
///
/// Reference: learn.microsoft.com/exchange/client-developer/web-service-reference
/// (FindItem, GetItem and GetFolder operations).
library;

import 'dart:math' as math;

import 'package:html/parser.dart' as html;

import '../../core/session.dart';
import '../../models/models.dart';

/// Schema version sent in every request's `RequestServerVersion` header.
/// Exchange2013 is the first schema that knows `item:Preview`.
const ewsServerVersion = 'Exchange2013';

const soapNamespace = 'http://schemas.xmlsoap.org/soap/envelope/';
const ewsTypesNamespace = 'http://schemas.microsoft.com/exchange/services/2006/types';
const ewsMessagesNamespace =
    'http://schemas.microsoft.com/exchange/services/2006/messages';

/// Response codes Exchange answers with when it does not know a requested
/// property such as `item:Preview` (Exchange before 2013): a schema
/// validation SOAP fault, or a response message with ErrorInvalidPropertyRequest.
const previewRejectionCodes = {'ErrorSchemaValidation', 'ErrorInvalidPropertyRequest'};

/// An EWS error: a SOAP fault, or a response message with
/// `ResponseClass="Error"`. [code] is Exchange's ResponseCode, e.g.
/// "ErrorItemNotFound". Never carries the server's message text.
class EwsError extends ParseError {
  final String code;
  EwsError(this.code) : super('mail ($code)');
}

// ---------------------------------------------------------------- requests

/// FindItem on a folder: ids plus subject, sender, the To line, received
/// time, read flag and (unless [withPreview] is false) the 256-character
/// preview, newest first.
String findItemsEnvelope({
  MailFolder folder = MailFolder.inbox,
  int limit = 30,
  int offset = 0,
  bool withPreview = true,
  String serverVersion = ewsServerVersion,
}) {
  final fields = [
    'item:Subject',
    'message:From',
    'item:DisplayTo',
    'item:DateTimeReceived',
    'message:IsRead',
    if (withPreview) 'item:Preview',
  ].map((f) => '\n        <t:FieldURI FieldURI="$f"/>').join();
  return _envelope('''
<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:AdditionalProperties>$fields
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="${limit.clamp(1, 1000)}" Offset="${math.max(offset, 0)}" BasePoint="Beginning"/>
  <m:SortOrder>
    <t:FieldOrder Order="Descending">
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
    </t:FieldOrder>
  </m:SortOrder>
  <m:ParentFolderIds>
    <t:DistinguishedFolderId Id="${folder.ewsId}"/>
  </m:ParentFolderIds>
</m:FindItem>''', serverVersion);
}

/// GetItem for one message: the header fields, the recipients, the
/// attachment list (names and sizes, no content) and the body, converted to
/// plain text by Exchange. Reading an item this way does not mark it read.
String getItemEnvelope(String id, {String serverVersion = ewsServerVersion}) =>
    _envelope('''
<m:GetItem>
  <m:ItemShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:BodyType>Text</t:BodyType>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="item:Subject"/>
      <t:FieldURI FieldURI="message:From"/>
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
      <t:FieldURI FieldURI="message:IsRead"/>
      <t:FieldURI FieldURI="item:Attachments"/>
      <t:FieldURI FieldURI="item:Body"/>
      <t:FieldURI FieldURI="message:ToRecipients"/>
      <t:FieldURI FieldURI="message:CcRecipients"/>
      <t:FieldURI FieldURI="message:BccRecipients"/>
      <t:FieldURI FieldURI="message:ReceivedBy"/>
      <t:FieldURI FieldURI="item:IsDraft"/>
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:ItemIds>
    <t:ItemId Id="${_escape(id)}"/>
  </m:ItemIds>
</m:GetItem>''', serverVersion);

/// UpdateItem setting `message:IsRead`. Read receipts the sender asked for
/// are suppressed: opening a message in the app must never send mail on the
/// student's behalf. No ChangeKey, so the flag is set whatever else changed.
String setReadEnvelope(String id, {bool read = true, String serverVersion = ewsServerVersion}) =>
    _envelope('''
<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite" SuppressReadReceipts="true">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="${_escape(id)}"/>
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="message:IsRead"/>
          <t:Message>
            <t:IsRead>$read</t:IsRead>
          </t:Message>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''', serverVersion);

/// GetFolder on the inbox for its unread count.
String getInboxFolderEnvelope({String serverVersion = ewsServerVersion}) => _envelope('''
<m:GetFolder>
  <m:FolderShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="folder:UnreadCount"/>
    </t:AdditionalProperties>
  </m:FolderShape>
  <m:FolderIds>
    <t:DistinguishedFolderId Id="inbox"/>
  </m:FolderIds>
</m:GetFolder>''', serverVersion);

/// GetFolder on every [MailFolder] at once, for the drawer's counts.
String getFolderCountsEnvelope({String serverVersion = ewsServerVersion}) => _envelope('''
<m:GetFolder>
  <m:FolderShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="folder:UnreadCount"/>
      <t:FieldURI FieldURI="folder:TotalCount"/>
    </t:AdditionalProperties>
  </m:FolderShape>
  <m:FolderIds>${MailFolder.values.map((f) => '\n    <t:DistinguishedFolderId Id="${f.ewsId}"/>').join()}
  </m:FolderIds>
</m:GetFolder>''', serverVersion);

/// CreateItem for a new message, a reply, a reply to all or a forward. With
/// [send] it goes out and a copy lands in Sent; without, it is saved to
/// Drafts. The body is plain text; for a reply or forward Exchange quotes the
/// original under it and adds the subject prefix. A reply's recipients are
/// Exchange's (the sender, or everyone but the student); a forward's are
/// [OutgoingMail.to], `cc` and `bcc`.
String createItemEnvelope(OutgoingMail m, {required bool send, String serverVersion = ewsServerVersion}) {
  final String item;
  switch (m.kind) {
    case ComposeKind.fresh:
      item = '''<t:Message>
      <t:Subject>${_escape(m.subject ?? '')}</t:Subject>
      <t:Body BodyType="Text">${_escape(m.body ?? '')}</t:Body>${_recipients(m)}
    </t:Message>''';
    case ComposeKind.reply || ComposeKind.replyAll || ComposeKind.forward:
      final tag = switch (m.kind) {
        ComposeKind.reply => 'ReplyToItem',
        ComposeKind.replyAll => 'ReplyAllToItem',
        _ => 'ForwardItem',
      };
      final ref = m.ref!;
      item = '''<t:$tag>${m.kind == ComposeKind.forward ? _recipients(m) : ''}
      ${_itemId(ref.id, ref.changeKey, 'ReferenceItemId')}
      <t:NewBodyContent BodyType="Text">${_escape(m.body ?? '')}</t:NewBodyContent>
    </t:$tag>''';
    case ComposeKind.draft:
      throw ArgumentError('A saved draft is updated, not created');
  }
  return _envelope('''
<m:CreateItem MessageDisposition="${send ? 'SendAndSaveCopy' : 'SaveOnly'}">
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="${send ? MailFolder.sent.ewsId : MailFolder.drafts.ewsId}"/>
  </m:SavedItemFolderId>
  <m:Items>
    $item
  </m:Items>
</m:CreateItem>''', serverVersion);
}

/// Whether [m], a saved draft, changes anything on it.
bool draftChanges(OutgoingMail m) =>
    m.subject != null || m.body != null || m.to != null || m.cc != null || m.bcc != null;

/// UpdateItem writing the changed fields of a saved draft ([OutgoingMail.ref]).
/// An emptied recipient line is deleted. The body is written as plain text,
/// so it is only sent when the student changed it.
String updateDraftEnvelope(OutgoingMail m, {String serverVersion = ewsServerVersion}) {
  String set(String field, String value) => '''
        <t:SetItemField>
          <t:FieldURI FieldURI="$field"/>
          <t:Message>$value</t:Message>
        </t:SetItemField>''';
  String line(String field, String element, List<String>? addresses) {
    if (addresses == null) return '';
    if (addresses.isEmpty) {
      return '''
        <t:DeleteItemField>
          <t:FieldURI FieldURI="$field"/>
        </t:DeleteItemField>''';
    }
    return set(field, _mailboxes(element, addresses));
  }

  return _envelope('''
<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="${_escape(m.ref!.id)}"/>
      <t:Updates>${[
        if (m.subject != null) set('item:Subject', '<t:Subject>${_escape(m.subject!)}</t:Subject>'),
        if (m.body != null) set('item:Body', '<t:Body BodyType="Text">${_escape(m.body!)}</t:Body>'),
        line('message:ToRecipients', 'ToRecipients', m.to),
        line('message:CcRecipients', 'CcRecipients', m.cc),
        line('message:BccRecipients', 'BccRecipients', m.bcc),
      ].join()}
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>''', serverVersion);
}

/// SendItem for a saved draft at its current [changeKey]; the sent copy goes
/// to Sent.
String sendItemEnvelope(String id, String changeKey, {String serverVersion = ewsServerVersion}) =>
    _envelope('''
<m:SendItem SaveItemToFolder="true">
  <m:ItemIds>
    ${_itemId(id, changeKey, 'ItemId')}
  </m:ItemIds>
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="${MailFolder.sent.ewsId}"/>
  </m:SavedItemFolderId>
</m:SendItem>''', serverVersion);

/// MoveItem to another folder. Deleting is a move to Deleted, as in Outlook,
/// so nothing the app does removes mail for good.
String moveItemEnvelope(String id, MailFolder to, {String serverVersion = ewsServerVersion}) => _envelope('''
<m:MoveItem>
  <m:ToFolderId>
    <t:DistinguishedFolderId Id="${to.ewsId}"/>
  </m:ToFolderId>
  <m:ItemIds>
    <t:ItemId Id="${_escape(id)}"/>
  </m:ItemIds>
</m:MoveItem>''', serverVersion);

/// ResolveNames: people and lists in the university directory and the
/// student's contacts whose name or address starts with [query].
String resolveNamesEnvelope(String query, {String serverVersion = ewsServerVersion}) => _envelope('''
<m:ResolveNames ReturnFullContactData="false" SearchScope="ActiveDirectoryContacts">
  <m:UnresolvedEntry>${_escape(query)}</m:UnresolvedEntry>
</m:ResolveNames>''', serverVersion);

String _itemId(String id, String changeKey, String element) => changeKey.isEmpty
    ? '<t:$element Id="${_escape(id)}"/>'
    : '<t:$element Id="${_escape(id)}" ChangeKey="${_escape(changeKey)}"/>';

/// The To, Cc and Bcc lines of [m], in schema order, leaving out empty ones.
String _recipients(OutgoingMail m) => [
      if (m.to?.isNotEmpty ?? false) _mailboxes('ToRecipients', m.to!),
      if (m.cc?.isNotEmpty ?? false) _mailboxes('CcRecipients', m.cc!),
      if (m.bcc?.isNotEmpty ?? false) _mailboxes('BccRecipients', m.bcc!),
    ].map((e) => '\n      $e').join();

String _mailboxes(String element, List<String> addresses) =>
    '<t:$element>${addresses.map((a) => '<t:Mailbox><t:EmailAddress>${_escape(a)}</t:EmailAddress></t:Mailbox>').join()}</t:$element>';

String _envelope(String body, String serverVersion) => '''
<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="$soapNamespace"
               xmlns:t="$ewsTypesNamespace"
               xmlns:m="$ewsMessagesNamespace">
<soap:Header>
  <t:RequestServerVersion Version="${_escape(serverVersion)}"/>
</soap:Header>
<soap:Body>
$body
</soap:Body>
</soap:Envelope>
''';

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

// --------------------------------------------------------------- responses

/// The inbox page from a FindItem response, in the server's order (newest
/// first, as requested). Item ids are kept verbatim; [MailHeader.from] is
/// the sender's display name, or the address when there is none.
List<MailHeader> parseFindItem(String xml) {
  final message = _responseMessage(xml, 'FindItem');
  final items = message.find('RootFolder')?.child('Items');
  if (items == null) throw ParseError('mail (FindItem)');
  return [
    // Message, MeetingRequest, ... : every item type carries the same fields.
    for (final item in items.elements)
      if (item.child('ItemId')?.attr('Id') case final id? when id.isNotEmpty)
        MailHeader(
          id: id,
          from: _sender(item),
          to: item.child('DisplayTo')?.text.trim() ?? '',
          subject: item.child('Subject')?.text.trim() ?? '',
          preview: _oneLine(item.child('Preview')?.text ?? ''),
          received: DateTime.tryParse(item.child('DateTimeReceived')?.text.trim() ?? '')
                  ?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
          unread: item.child('IsRead')?.text.trim().toLowerCase() == 'false',
        ),
  ];
}

/// The plain-text body from a GetItem response, with `\n` line breaks.
String parseGetItem(String xml) => _body(_getItem(xml));

/// The whole message from a GetItem response made with [getItemEnvelope].
/// Inline attachments (pictures inside the body) are left out of
/// [MailMessage.attachments]; they are not files the student sent or gets.
MailMessage parseMessage(String xml) {
  final item = _getItem(xml);
  final id = item.child('ItemId')?.attr('Id') ?? '';
  if (id.isEmpty) throw ParseError('mail (GetItem)');
  final mailbox = item.child('From')?.child('Mailbox');
  return MailMessage(
    id: id,
    changeKey: item.child('ItemId')?.attr('ChangeKey') ?? '',
    from: _sender(item),
    fromAddress: mailbox?.child('EmailAddress')?.text.trim() ?? '',
    subject: item.child('Subject')?.text.trim() ?? '',
    received: DateTime.tryParse(item.child('DateTimeReceived')?.text.trim() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    unread: item.child('IsRead')?.text.trim().toLowerCase() == 'false',
    body: _body(item),
    attachments: [
      for (final a in item.child('Attachments')?.elements ?? const <SoapElement>[])
        if (a.child('IsInline')?.text.trim().toLowerCase() != 'true')
          MailAttachment(
            name: a.child('Name')?.text.trim() ?? '',
            size: int.tryParse(a.child('Size')?.text.trim() ?? '') ?? 0,
          ),
    ],
    to: _addresses(item.child('ToRecipients')),
    cc: _addresses(item.child('CcRecipients')),
    bcc: _addresses(item.child('BccRecipients')),
    receivedBy: item.child('ReceivedBy')?.find('EmailAddress')?.text.trim() ?? '',
    isDraft: item.child('IsDraft')?.text.trim().toLowerCase() == 'true',
  );
}

List<MailAddress> _addresses(SoapElement? line) => [
      for (final m in line?.elements ?? const <SoapElement>[])
        if (m.isNamed('Mailbox'))
          MailAddress(m.child('Name')?.text.trim() ?? '', m.child('EmailAddress')?.text.trim() ?? ''),
    ];

/// The id and change key of the item an UpdateItem, CreateItem or MoveItem
/// response carries, or null when it carries none (a message sent straight
/// away, a move across mailboxes). Throws [EwsError] when Exchange refused.
(String, String)? parseItemId(String xml, String operation) {
  final id = _responseMessage(xml, operation).find('ItemId');
  final value = id?.attr('Id') ?? '';
  return value.isEmpty ? null : (value, id!.attr('ChangeKey') ?? '');
}

/// Checks a SendItem response; throws [EwsError] when Exchange refused.
void parseSendItem(String xml) => _responseMessage(xml, 'SendItem');

/// Each folder's counts from a [getFolderCountsEnvelope] response. A folder
/// Exchange answered with an error for (one the mailbox lacks) is left out.
Map<MailFolder, MailFolderCount> parseFolderCounts(String xml) {
  final messages = _responseMessages(xml, 'GetFolder');
  return {
    for (final (i, m) in messages.indexed)
      if (i < MailFolder.values.length && m.attr('ResponseClass')?.toLowerCase() != 'error')
        MailFolder.values[i]: MailFolderCount(
          int.tryParse(m.find('UnreadCount')?.text.trim() ?? '') ?? 0,
          int.tryParse(m.find('TotalCount')?.text.trim() ?? '') ?? 0,
        ),
  };
}

/// The people and lists from a ResolveNames response that have an SMTP
/// address; none when nothing matched.
List<MailAddress> parseResolveNames(String xml) {
  final SoapElement message;
  try {
    message = _responseMessage(xml, 'ResolveNames');
  } on EwsError catch (e) {
    if (e.code == 'ErrorNameResolutionNoResults') return const [];
    rethrow;
  }
  final seen = <String>{};
  final out = <MailAddress>[];
  for (final r in message.find('ResolutionSet')?.elements ?? const <SoapElement>[]) {
    final m = r.child('Mailbox');
    final a = MailAddress(m?.child('Name')?.text.trim() ?? '', m?.child('EmailAddress')?.text.trim() ?? '');
    if (a.address.contains('@') && seen.add(a.address.toLowerCase())) out.add(a);
  }
  return out;
}

/// Checks an UpdateItem response; throws [EwsError] when Exchange refused.
void parseUpdateItem(String xml) => _responseMessage(xml, 'UpdateItem');

SoapElement _getItem(String xml) {
  final message = _responseMessage(xml, 'GetItem');
  final item = message.child('Items')?.elements.firstOrNull;
  if (item == null) throw ParseError('mail (GetItem)');
  return item;
}

String _body(SoapElement item) {
  final body = item.child('Body');
  if (body == null) return '';
  var text = body.text;
  // Asked for Text; should the server still send HTML, strip the markup.
  if (body.attr('BodyType')?.toLowerCase() == 'html') {
    text = html.parse(text).body?.text ?? text;
  }
  // Exchange's HTML-to-text conversion leaves long runs of empty lines and
  // lines of only spaces or invisible padding (layout tables, the zero-width
  // characters newsletters pad their preview text with); keep one blank
  // line between paragraphs.
  return text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(_blankLineEnd, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// The inbox unread count from a GetFolder response.
int parseGetFolder(String xml) {
  final message = _responseMessage(xml, 'GetFolder');
  final count = int.tryParse(message.find('UnreadCount')?.text.trim() ?? '');
  if (count == null) throw ParseError('mail (UnreadCount)');
  return count;
}

/// The error in a SOAP fault body (Exchange sends these with HTTP 500), or
/// null when [xml] is not a SOAP fault.
EwsError? ewsFault(String xml) {
  final SoapElement doc;
  try {
    doc = readSoap(xml);
  } on FormatException {
    return null;
  }
  final fault = doc.find('Fault');
  return fault == null ? null : EwsError(_faultCode(fault));
}

/// The `<m:XxxResponseMessage>` of [operation], after turning SOAP faults
/// and `ResponseClass="Error"` into [EwsError].
SoapElement _responseMessage(String xml, String operation) {
  final SoapElement doc;
  try {
    doc = readSoap(xml);
  } on FormatException {
    throw ParseError('mail ($operation)');
  }
  final fault = doc.find('Fault');
  if (fault != null) throw EwsError(_faultCode(fault));
  final message = doc.find('${operation}ResponseMessage');
  if (message == null) throw ParseError('mail ($operation)');
  if (message.attr('ResponseClass')?.toLowerCase() == 'error') {
    final code = message.child('ResponseCode')?.text.trim() ?? '';
    throw EwsError(code.isEmpty ? 'Error' : code);
  }
  return message;
}

/// Every `<m:XxxResponseMessage>` of [operation], in order, after turning a
/// SOAP fault into [EwsError]. Per-message errors are left to the caller.
List<SoapElement> _responseMessages(String xml, String operation) {
  final SoapElement doc;
  try {
    doc = readSoap(xml);
  } on FormatException {
    throw ParseError('mail ($operation)');
  }
  final fault = doc.find('Fault');
  if (fault != null) throw EwsError(_faultCode(fault));
  final messages =
      doc.find('ResponseMessages')?.elements.where((e) => e.isNamed('${operation}ResponseMessage')).toList();
  if (messages == null || messages.isEmpty) throw ParseError('mail ($operation)');
  return messages;
}

/// `<detail><e:ResponseCode>` when present, else `<faultcode>` minus its prefix.
String _faultCode(SoapElement fault) {
  final code = fault.find('ResponseCode')?.text.trim() ?? '';
  if (code.isNotEmpty) return code;
  final faultCode = fault.child('faultcode')?.text.trim() ?? '';
  final local = faultCode.substring(faultCode.indexOf(':') + 1);
  return local.isEmpty ? 'SoapFault' : local;
}

/// Spaces and invisible characters (separators, format characters such as
/// zero-width spaces and soft hyphens, the combining grapheme joiner) at the
/// end of a line, or making up the whole line.
final _blankLineEnd = RegExp(r'[\p{Z}\p{Cf}͏\t]+$', multiLine: true, unicode: true);

String _sender(SoapElement item) {
  final mailbox = item.child('From')?.child('Mailbox');
  final name = mailbox?.child('Name')?.text.trim() ?? '';
  if (name.isNotEmpty) return name;
  return mailbox?.child('EmailAddress')?.text.trim() ?? '';
}

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

// ------------------------------------------------------------- XML reader

/// An element from [readSoap]. Names are matched by local name (prefix
/// dropped) and case-insensitively, so `t:Subject`, `Subject` and
/// `m:subject` all match `child('Subject')`.
class SoapElement {
  SoapElement(this.qualifiedName, this.attributes);

  /// As written, e.g. "t:Subject".
  final String qualifiedName;

  /// Qualified attribute names as written, values with entities decoded.
  final Map<String, String> attributes;

  final List<Object> _content = []; // String text or SoapElement children

  /// "Subject" for "t:Subject".
  String get name => qualifiedName.substring(qualifiedName.indexOf(':') + 1);

  bool isNamed(String localName) => name.toLowerCase() == localName.toLowerCase();

  Iterable<SoapElement> get elements => _content.whereType<SoapElement>();

  /// All text inside, entities decoded.
  String get text {
    final out = StringBuffer();
    _writeText(out);
    return out.toString();
  }

  void _writeText(StringBuffer out) {
    for (final c in _content) {
      c is String ? out.write(c) : (c as SoapElement)._writeText(out);
    }
  }

  /// Attribute by local name, e.g. `attr('Id')`.
  String? attr(String localName) {
    final want = localName.toLowerCase();
    for (final e in attributes.entries) {
      if (e.key.substring(e.key.indexOf(':') + 1).toLowerCase() == want) return e.value;
    }
    return null;
  }

  /// First direct child named [localName].
  SoapElement? child(String localName) {
    for (final e in elements) {
      if (e.isNamed(localName)) return e;
    }
    return null;
  }

  /// First descendant named [localName], depth first.
  SoapElement? find(String localName) {
    for (final e in elements) {
      if (e.isNamed(localName)) return e;
      final hit = e.find(localName);
      if (hit != null) return hit;
    }
    return null;
  }
}

/// A small non-validating XML reader for SOAP responses (package:xml is not
/// a dependency, and an HTML parser mishandles self-closing tags). Handles
/// prefixes, self-closing tags, CDATA, comments, processing instructions and
/// the XML entities. Returns a document node whose children are the
/// top-level elements. Throws [FormatException] on a broken tag.
SoapElement readSoap(String xml) {
  // XML end-of-line handling: literal CR LF and CR read as LF. An escaped
  // &#xD; still decodes to CR.
  xml = xml.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final document = SoapElement('#document', const {});
  final open = [document];
  var i = 0;
  while (i < xml.length) {
    final lt = xml.indexOf('<', i);
    if (lt < 0) {
      open.last._content.add(_decode(xml.substring(i)));
      break;
    }
    if (lt > i) open.last._content.add(_decode(xml.substring(i, lt)));

    if (xml.startsWith('<![CDATA[', lt)) {
      final end = _indexOf(xml, ']]>', lt + 9);
      open.last._content.add(xml.substring(lt + 9, end));
      i = end + 3;
    } else if (xml.startsWith('<!--', lt)) {
      i = _indexOf(xml, '-->', lt + 4) + 3;
    } else if (xml.startsWith('<?', lt)) {
      i = _indexOf(xml, '?>', lt + 2) + 2;
    } else if (xml.startsWith('<!', lt)) {
      i = _indexOf(xml, '>', lt + 2) + 1;
    } else if (xml.startsWith('</', lt)) {
      final gt = _indexOf(xml, '>', lt + 2);
      final name = xml.substring(lt + 2, gt).trim();
      // Close the matching open element; a stray end tag is ignored.
      final at = open.lastIndexWhere((e) => e.qualifiedName == name);
      if (at > 0) open.removeRange(at, open.length);
      i = gt + 1;
    } else {
      final tag = _startTag.matchAsPrefix(xml, lt);
      if (tag == null) throw FormatException('Bad start tag', xml, lt);
      final attributes = {
        for (final a in _attribute.allMatches(tag[2]!)) a[1]!: _decode(a[2] ?? a[3]!),
      };
      final element = SoapElement(tag[1]!, attributes);
      open.last._content.add(element);
      if (tag[3] != '/') open.add(element);
      i = tag.end;
    }
  }
  return document;
}

final _startTag = RegExp(
    r'''<([^\s/>!?]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(/?)>''');
final _attribute = RegExp(r'''([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
final _entity = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|lt|gt|amp|quot|apos);');

int _indexOf(String xml, String token, int from) {
  final at = xml.indexOf(token, from);
  if (at < 0) throw FormatException('Missing $token', xml, from);
  return at;
}

String _decode(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entity, (m) {
    final e = m[1]!;
    switch (e) {
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'amp':
        return '&';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final hex = e[1] == 'x' || e[1] == 'X';
    final code = int.tryParse(e.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
    if (code == null || code > 0x10FFFF) return m[0]!;
    return String.fromCharCode(code);
  });
}
