// Exchange Web Services SOAP: request envelopes and response readers for the
// mail client (docs/ENDPOINTS.md, Mail). Pure functions, no I/O. A port of
// lib/services/mail/ews_soap.dart.
//
// Reference: learn.microsoft.com/exchange/client-developer/web-service-reference
// (FindItem, GetItem, GetFolder, CreateItem, CreateAttachment, UpdateItem,
// SendItem, MoveItem, ResolveNames and GetAttachment operations).
//
// Responses are read with readSoap, a small XML reader of our own, not
// DOMParser: the service worker has no DOMParser, and linkedom's text/xml
// mode finds no elements in a SOAP envelope (getElementsByTagName('*') comes
// back empty). The app's Dart client uses the same reader for the same reason.

import { ParseError } from '../../core/errors.ts';
import { parseHtml } from '../../core/dom.ts';
import {
  mailFolders,
  type MailAddress,
  type MailAttachment,
  type MailFolder,
  type MailFolderCount,
  type MailHeader,
  type MailMessage,
  type OutgoingAttachment,
  type OutgoingMail,
} from '../../core/models.ts';

/** Schema version sent in every request's RequestServerVersion header. Exchange2013 is the first that knows item:Preview. */
export const ewsServerVersion = 'Exchange2013';

export const soapNamespace = 'http://schemas.xmlsoap.org/soap/envelope/';
export const ewsTypesNamespace = 'http://schemas.microsoft.com/exchange/services/2006/types';
export const ewsMessagesNamespace = 'http://schemas.microsoft.com/exchange/services/2006/messages';

/**
 * Response codes Exchange answers with when it does not know a requested
 * property such as item:Preview (Exchange before 2013): a schema validation
 * SOAP fault, or a response message with ErrorInvalidPropertyRequest.
 */
export const previewRejectionCodes = new Set(['ErrorSchemaValidation', 'ErrorInvalidPropertyRequest']);

/**
 * An EWS error: a SOAP fault, or a response message with ResponseClass="Error".
 * code is Exchange's ResponseCode, e.g. "ErrorItemNotFound". Never carries the
 * server's message text.
 */
export class EwsError extends ParseError {
  readonly code: string;
  constructor(code: string) {
    super(`mail (${code})`);
    this.name = 'EwsError';
    this.code = code;
  }
}

const ewsId = (f: MailFolder): string => mailFolders.find((x) => x.id === f)!.ews;

// ---------------------------------------------------------------- requests

/**
 * FindItem on a folder: ids plus subject, sender, the To line, received time,
 * read flag, whether it has attachments and (unless withPreview is false) the
 * 256-character preview, newest first. With queryString, only what Exchange's
 * search finds for it.
 */
export function findItemsEnvelope({
  folder = 'inbox' as MailFolder,
  limit = 30,
  offset = 0,
  withPreview = true,
  queryString = '',
  serverVersion = ewsServerVersion,
} = {}): string {
  const fields = [
    'item:Subject',
    'message:From',
    'item:DisplayTo',
    'item:DateTimeReceived',
    'message:IsRead',
    'item:HasAttachments',
    ...(withPreview ? ['item:Preview'] : []),
  ]
    .map((f) => `\n        <t:FieldURI FieldURI="${f}"/>`)
    .join('');
  return envelope(
    `
<m:FindItem Traversal="Shallow">
  <m:ItemShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:AdditionalProperties>${fields}
    </t:AdditionalProperties>
  </m:ItemShape>
  <m:IndexedPageItemView MaxEntriesReturned="${Math.min(Math.max(Math.trunc(limit), 1), 1000)}" Offset="${Math.max(Math.trunc(offset), 0)}" BasePoint="Beginning"/>
  <m:SortOrder>
    <t:FieldOrder Order="Descending">
      <t:FieldURI FieldURI="item:DateTimeReceived"/>
    </t:FieldOrder>
  </m:SortOrder>
  <m:ParentFolderIds>
    <t:DistinguishedFolderId Id="${ewsId(folder)}"/>
  </m:ParentFolderIds>${queryString === '' ? '' : `\n  <m:QueryString>${escape(queryString)}</m:QueryString>`}
</m:FindItem>`,
    serverVersion,
  );
}

/**
 * GetItem for one message: the header fields, the recipients, the attachment
 * list (names and sizes, no content) and the body, converted to plain text by
 * Exchange. Reading an item this way does not mark it read.
 */
export function getItemEnvelope(id: string, serverVersion = ewsServerVersion): string {
  return envelope(
    `
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
    <t:ItemId Id="${escape(id)}"/>
  </m:ItemIds>
</m:GetItem>`,
    serverVersion,
  );
}

/**
 * UpdateItem setting message:IsRead. Read receipts the sender asked for are
 * suppressed: opening a message must never send mail on the student's behalf.
 * No ChangeKey, so the flag is set whatever else changed.
 */
export function setReadEnvelope(id: string, read = true, serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite" SuppressReadReceipts="true">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="${escape(id)}"/>
      <t:Updates>
        <t:SetItemField>
          <t:FieldURI FieldURI="message:IsRead"/>
          <t:Message>
            <t:IsRead>${read}</t:IsRead>
          </t:Message>
        </t:SetItemField>
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>`,
    serverVersion,
  );
}

/** GetFolder on the inbox for its unread count. */
export function getInboxFolderEnvelope(serverVersion = ewsServerVersion): string {
  return envelope(
    `
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
</m:GetFolder>`,
    serverVersion,
  );
}

/** GetFolder on every mail folder at once, for the sidebar's counts. */
export function getFolderCountsEnvelope(serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:GetFolder>
  <m:FolderShape>
    <t:BaseShape>IdOnly</t:BaseShape>
    <t:AdditionalProperties>
      <t:FieldURI FieldURI="folder:UnreadCount"/>
      <t:FieldURI FieldURI="folder:TotalCount"/>
    </t:AdditionalProperties>
  </m:FolderShape>
  <m:FolderIds>${mailFolders.map((f) => `\n    <t:DistinguishedFolderId Id="${f.ews}"/>`).join('')}
  </m:FolderIds>
</m:GetFolder>`,
    serverVersion,
  );
}

/**
 * CreateItem for a new message, a reply, a reply to all or a forward. With
 * send it goes out and a copy lands in Sent; without, it is saved to Drafts.
 * The body is plain text; for a reply or forward Exchange quotes the original
 * under it and adds the subject prefix. A reply's recipients are Exchange's
 * (the sender, or everyone but the student); a forward's are m.to, cc and bcc.
 */
export function createItemEnvelope(m: OutgoingMail, send: boolean, serverVersion = ewsServerVersion): string {
  let item: string;
  switch (m.kind) {
    case 'fresh':
      item = `<t:Message>
      <t:Subject>${escape(m.subject ?? '')}</t:Subject>
      <t:Body BodyType="Text">${escape(m.body ?? '')}</t:Body>${recipients(m)}
    </t:Message>`;
      break;
    case 'reply':
    case 'replyAll':
    case 'forward': {
      const tag = m.kind === 'reply' ? 'ReplyToItem' : m.kind === 'replyAll' ? 'ReplyAllToItem' : 'ForwardItem';
      if (!m.ref) throw new Error(`A ${m.kind} needs the original message`);
      item = `<t:${tag}>${m.kind === 'forward' ? recipients(m) : ''}
      ${itemId(m.ref.id, m.ref.changeKey, 'ReferenceItemId')}
      <t:NewBodyContent BodyType="Text">${escape(m.body ?? '')}</t:NewBodyContent>
    </t:${tag}>`;
      break;
    }
    case 'draft':
      throw new Error('A saved draft is updated, not created');
  }
  return envelope(
    `
<m:CreateItem MessageDisposition="${send ? 'SendAndSaveCopy' : 'SaveOnly'}">
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="${send ? ewsId('sent') : ewsId('drafts')}"/>
  </m:SavedItemFolderId>
  <m:Items>
    ${item}
  </m:Items>
</m:CreateItem>`,
    serverVersion,
  );
}

/**
 * CreateAttachment adding one file to a saved message. Exchange moves the
 * message's change key on: parseCreateAttachment returns the new one.
 */
export function createAttachmentEnvelope(parent: { id: string; changeKey: string }, file: OutgoingAttachment, serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:CreateAttachment>
  ${itemId(parent.id, parent.changeKey, 'ParentItemId').replace('<t:', '<m:')}
  <m:Attachments>
    <t:FileAttachment>
      <t:Name>${escape(file.name)}</t:Name>
      <t:ContentType>${escape(file.contentType || 'application/octet-stream')}</t:ContentType>
      <t:Content>${escape(file.base64)}</t:Content>
    </t:FileAttachment>
  </m:Attachments>
</m:CreateAttachment>`,
    serverVersion,
  );
}

/** Whether m, a saved draft, changes anything on it. */
export const draftChanges = (m: OutgoingMail): boolean =>
  m.subject != null || m.body != null || m.to != null || m.cc != null || m.bcc != null;

/**
 * UpdateItem writing the changed fields of a saved draft (m.ref). An emptied
 * recipient line is deleted. The body is written as plain text, so it is only
 * sent when the student changed it (it would flatten a reply draft's quoted HTML).
 */
export function updateDraftEnvelope(m: OutgoingMail, serverVersion = ewsServerVersion): string {
  if (!m.ref) throw new Error('A draft update needs the saved draft');
  const set = (field: string, value: string) => `
        <t:SetItemField>
          <t:FieldURI FieldURI="${field}"/>
          <t:Message>${value}</t:Message>
        </t:SetItemField>`;
  const line = (field: string, element: string, addresses: string[] | undefined) => {
    if (addresses == null) return '';
    if (addresses.length === 0) {
      return `
        <t:DeleteItemField>
          <t:FieldURI FieldURI="${field}"/>
        </t:DeleteItemField>`;
    }
    return set(field, mailboxes(element, addresses));
  };
  const updates = [
    m.subject != null ? set('item:Subject', `<t:Subject>${escape(m.subject)}</t:Subject>`) : '',
    m.body != null ? set('item:Body', `<t:Body BodyType="Text">${escape(m.body)}</t:Body>`) : '',
    line('message:ToRecipients', 'ToRecipients', m.to),
    line('message:CcRecipients', 'CcRecipients', m.cc),
    line('message:BccRecipients', 'BccRecipients', m.bcc),
  ].join('');
  return envelope(
    `
<m:UpdateItem MessageDisposition="SaveOnly" ConflictResolution="AlwaysOverwrite">
  <m:ItemChanges>
    <t:ItemChange>
      <t:ItemId Id="${escape(m.ref.id)}"/>
      <t:Updates>${updates}
      </t:Updates>
    </t:ItemChange>
  </m:ItemChanges>
</m:UpdateItem>`,
    serverVersion,
  );
}

/** SendItem for a saved draft at its current changeKey; the sent copy goes to Sent. */
export function sendItemEnvelope(id: string, changeKey: string, serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:SendItem SaveItemToFolder="true">
  <m:ItemIds>
    ${itemId(id, changeKey, 'ItemId')}
  </m:ItemIds>
  <m:SavedItemFolderId>
    <t:DistinguishedFolderId Id="${ewsId('sent')}"/>
  </m:SavedItemFolderId>
</m:SendItem>`,
    serverVersion,
  );
}

/** MoveItem to another folder. Deleting is a move to Deleted, as in Outlook, so nothing removes mail for good. */
export function moveItemEnvelope(id: string, to: MailFolder, serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:MoveItem>
  <m:ToFolderId>
    <t:DistinguishedFolderId Id="${ewsId(to)}"/>
  </m:ToFolderId>
  <m:ItemIds>
    <t:ItemId Id="${escape(id)}"/>
  </m:ItemIds>
</m:MoveItem>`,
    serverVersion,
  );
}

/** ResolveNames: people and lists in the university directory and the student's contacts whose name or address starts with query. */
export function resolveNamesEnvelope(query: string, serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:ResolveNames ReturnFullContactData="false" SearchScope="ActiveDirectoryContacts">
  <m:UnresolvedEntry>${escape(query)}</m:UnresolvedEntry>
</m:ResolveNames>`,
    serverVersion,
  );
}

/** GetAttachment for one attachment's content (base64, as Exchange sends it). */
export function getAttachmentEnvelope(id: string, serverVersion = ewsServerVersion): string {
  return envelope(
    `
<m:GetAttachment>
  <m:AttachmentIds>
    <t:AttachmentId Id="${escape(id)}"/>
  </m:AttachmentIds>
</m:GetAttachment>`,
    serverVersion,
  );
}

const itemId = (id: string, changeKey: string, element: string): string =>
  changeKey === ''
    ? `<t:${element} Id="${escape(id)}"/>`
    : `<t:${element} Id="${escape(id)}" ChangeKey="${escape(changeKey)}"/>`;

/** The To, Cc and Bcc lines of m, in schema order, leaving out empty ones. */
const recipients = (m: OutgoingMail): string =>
  [
    m.to?.length ? mailboxes('ToRecipients', m.to) : '',
    m.cc?.length ? mailboxes('CcRecipients', m.cc) : '',
    m.bcc?.length ? mailboxes('BccRecipients', m.bcc) : '',
  ]
    .filter((e) => e !== '')
    .map((e) => `\n      ${e}`)
    .join('');

const mailboxes = (element: string, addresses: string[]): string =>
  `<t:${element}>${addresses.map((a) => `<t:Mailbox><t:EmailAddress>${escape(a)}</t:EmailAddress></t:Mailbox>`).join('')}</t:${element}>`;

const envelope = (body: string, serverVersion: string): string => `<?xml version="1.0" encoding="utf-8"?>
<soap:Envelope xmlns:soap="${soapNamespace}"
               xmlns:t="${ewsTypesNamespace}"
               xmlns:m="${ewsMessagesNamespace}">
<soap:Header>
  <t:RequestServerVersion Version="${escape(serverVersion)}"/>
</soap:Header>
<soap:Body>
${body}
</soap:Body>
</soap:Envelope>
`;

const escape = (s: string): string =>
  s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');

// --------------------------------------------------------------- responses

/**
 * A folder page from a FindItem response, in the server's order (newest
 * first, as requested). Item ids are kept verbatim; from is the sender's
 * display name, or the address when there is none.
 */
export function parseFindItem(xml: string): MailHeader[] {
  const message = responseMessage(xml, 'FindItem');
  const items = message.find('RootFolder')?.child('Items');
  if (!items) throw new ParseError('mail (FindItem)');
  const out: MailHeader[] = [];
  // Message, MeetingRequest, ...: every item type carries the same fields.
  for (const item of items.elements) {
    const id = item.child('ItemId')?.attr('Id');
    if (!id) continue;
    out.push({
      id,
      from: sender(item),
      to: item.child('DisplayTo')?.text.trim() ?? '',
      subject: item.child('Subject')?.text.trim() ?? '',
      preview: oneLine(item.child('Preview')?.text ?? ''),
      received: time(item.child('DateTimeReceived')),
      unread: flag(item.child('IsRead')) === false,
      hasAttachments: flag(item.child('HasAttachments')) === true,
    });
  }
  return out;
}

/** The plain-text body from a GetItem response, with \n line breaks. */
export const parseGetItem = (xml: string): string => body(getItem(xml));

/**
 * The whole message from a GetItem response made with getItemEnvelope.
 * Inline attachments (pictures inside the body) are left out of attachments;
 * they are not files the student sent or gets.
 */
export function parseMessage(xml: string): MailMessage {
  const item = getItem(xml);
  const idEl = item.child('ItemId');
  const id = idEl?.attr('Id') ?? '';
  if (id === '') throw new ParseError('mail (GetItem)');
  const mailbox = item.child('From')?.child('Mailbox');
  const attachments: MailAttachment[] = [];
  for (const a of item.child('Attachments')?.elements ?? []) {
    if (flag(a.child('IsInline')) === true) continue;
    attachments.push({
      id: a.child('AttachmentId')?.attr('Id') ?? '',
      name: a.child('Name')?.text.trim() ?? '',
      size: int(a.child('Size')) ?? 0,
    });
  }
  return {
    id,
    changeKey: idEl?.attr('ChangeKey') ?? '',
    from: sender(item),
    fromAddress: mailbox?.child('EmailAddress')?.text.trim() ?? '',
    subject: item.child('Subject')?.text.trim() ?? '',
    received: time(item.child('DateTimeReceived')),
    unread: flag(item.child('IsRead')) === false,
    body: body(item),
    attachments,
    to: addresses(item.child('ToRecipients')),
    cc: addresses(item.child('CcRecipients')),
    bcc: addresses(item.child('BccRecipients')),
    receivedBy: item.child('ReceivedBy')?.find('EmailAddress')?.text.trim() ?? '',
    isDraft: flag(item.child('IsDraft')) === true,
  };
}

const addresses = (line: SoapElement | null): MailAddress[] =>
  (line?.elements ?? [])
    .filter((m) => m.isNamed('Mailbox'))
    .map((m) => ({ name: m.child('Name')?.text.trim() ?? '', address: m.child('EmailAddress')?.text.trim() ?? '' }));

/**
 * The id and change key of the item an UpdateItem, CreateItem or MoveItem
 * response carries, or null when it carries none (a message sent straight
 * away, a move across mailboxes). Throws EwsError when Exchange refused.
 */
export function parseItemId(xml: string, operation: string): { id: string; changeKey: string } | null {
  const id = responseMessage(xml, operation).find('ItemId');
  const value = id?.attr('Id') ?? '';
  return value === '' ? null : { id: value, changeKey: id!.attr('ChangeKey') ?? '' };
}

/**
 * The message an attachment went onto, at its new change key, from a
 * CreateAttachment response; null when Exchange didn't say. Throws EwsError
 * when Exchange refused.
 */
export function parseCreateAttachment(xml: string): { id: string; changeKey: string } | null {
  const attachment = responseMessage(xml, 'CreateAttachment').find('AttachmentId');
  const id = attachment?.attr('RootItemId') ?? '';
  return id === '' ? null : { id, changeKey: attachment!.attr('RootItemChangeKey') ?? '' };
}

/** Checks a SendItem response; throws EwsError when Exchange refused. */
export function parseSendItem(xml: string): void {
  responseMessage(xml, 'SendItem');
}

/** Checks an UpdateItem response; throws EwsError when Exchange refused. */
export function parseUpdateItem(xml: string): void {
  responseMessage(xml, 'UpdateItem');
}

/** Each folder's counts from a getFolderCountsEnvelope response. A folder Exchange answered with an error for (one the mailbox lacks) is left out. */
export function parseFolderCounts(xml: string): Partial<Record<MailFolder, MailFolderCount>> {
  const out: Partial<Record<MailFolder, MailFolderCount>> = {};
  responseMessages(xml, 'GetFolder').forEach((m, i) => {
    if (i >= mailFolders.length || m.attr('ResponseClass')?.toLowerCase() === 'error') return;
    out[mailFolders[i].id] = { unread: int(m.find('UnreadCount')) ?? 0, total: int(m.find('TotalCount')) ?? 0 };
  });
  return out;
}

/** The people and lists from a ResolveNames response that have an SMTP address; none when nothing matched. */
export function parseResolveNames(xml: string): MailAddress[] {
  let message: SoapElement;
  try {
    message = responseMessage(xml, 'ResolveNames');
  } catch (e) {
    if (e instanceof EwsError && e.code === 'ErrorNameResolutionNoResults') return [];
    throw e;
  }
  const seen = new Set<string>();
  const out: MailAddress[] = [];
  for (const r of message.find('ResolutionSet')?.elements ?? []) {
    const m = r.child('Mailbox');
    const a = { name: m?.child('Name')?.text.trim() ?? '', address: m?.child('EmailAddress')?.text.trim() ?? '' };
    const key = a.address.toLowerCase();
    if (a.address.includes('@') && !seen.has(key)) {
      seen.add(key);
      out.push(a);
    }
  }
  return out;
}

/**
 * A file attachment's content from a GetAttachment response. An attached
 * message (ItemAttachment) has no file content and is a ParseError.
 */
export function parseAttachment(xml: string): { name: string; contentType: string; base64: string } {
  const message = responseMessage(xml, 'GetAttachment');
  const file = message.find('FileAttachment');
  const content = file?.child('Content');
  if (!file || !content) throw new ParseError('mail (GetAttachment)');
  return {
    name: file.child('Name')?.text.trim() ?? '',
    contentType: file.child('ContentType')?.text.trim() || 'application/octet-stream',
    base64: content.text.replace(/\s+/g, ''),
  };
}

/** The inbox unread count from a GetFolder response. */
export function parseGetFolder(xml: string): number {
  const count = int(responseMessage(xml, 'GetFolder').find('UnreadCount'));
  if (count == null) throw new ParseError('mail (UnreadCount)');
  return count;
}

/** The error in a SOAP fault body (Exchange sends these with HTTP 500), or null when xml is not a SOAP fault. */
export function ewsFault(xml: string): EwsError | null {
  let doc: SoapElement;
  try {
    doc = readSoap(xml);
  } catch {
    return null;
  }
  const fault = doc.find('Fault');
  return fault ? new EwsError(faultCode(fault)) : null;
}

function getItem(xml: string): SoapElement {
  const item = responseMessage(xml, 'GetItem').child('Items')?.elements[0];
  if (!item) throw new ParseError('mail (GetItem)');
  return item;
}

function body(item: SoapElement): string {
  const b = item.child('Body');
  if (!b) return '';
  let text = b.text;
  // Asked for Text; should the server still send HTML, strip the markup.
  if (b.attr('BodyType')?.toLowerCase() === 'html') text = htmlText(text);
  // Exchange's HTML-to-text conversion leaves long runs of empty lines and
  // lines of only spaces or invisible padding (layout tables, the zero-width
  // characters newsletters pad their preview text with); keep one blank line
  // between paragraphs.
  return text
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n')
    .replace(blankLineEnd, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/** HTML markup to its text: the DOM's where there is one, else tags dropped and entities decoded. */
function htmlText(html: string): string {
  if (typeof DOMParser !== 'undefined') {
    const doc = parseHtml(html);
    return doc.body?.textContent ?? doc.documentElement?.textContent ?? html;
  }
  return decode(html.replace(/<(script|style)[\s\S]*?<\/\1>/gi, '').replace(/<[^>]*>/g, ''));
}

/** The <m:XxxResponseMessage> of operation, after turning SOAP faults and ResponseClass="Error" into EwsError. */
function responseMessage(xml: string, operation: string): SoapElement {
  const doc = readOrThrow(xml, operation);
  const fault = doc.find('Fault');
  if (fault) throw new EwsError(faultCode(fault));
  const message = doc.find(`${operation}ResponseMessage`);
  if (!message) throw new ParseError(`mail (${operation})`);
  if (message.attr('ResponseClass')?.toLowerCase() === 'error') {
    const code = message.child('ResponseCode')?.text.trim() ?? '';
    throw new EwsError(code === '' ? 'Error' : code);
  }
  return message;
}

/** Every <m:XxxResponseMessage> of operation, in order, after turning a SOAP fault into EwsError. Per-message errors are left to the caller. */
function responseMessages(xml: string, operation: string): SoapElement[] {
  const doc = readOrThrow(xml, operation);
  const fault = doc.find('Fault');
  if (fault) throw new EwsError(faultCode(fault));
  const messages = doc.find('ResponseMessages')?.elements.filter((e) => e.isNamed(`${operation}ResponseMessage`));
  if (!messages?.length) throw new ParseError(`mail (${operation})`);
  return messages;
}

function readOrThrow(xml: string, operation: string): SoapElement {
  try {
    return readSoap(xml);
  } catch {
    throw new ParseError(`mail (${operation})`);
  }
}

/** <detail><e:ResponseCode> when present, else <faultcode> minus its prefix. */
function faultCode(fault: SoapElement): string {
  const code = fault.find('ResponseCode')?.text.trim() ?? '';
  if (code !== '') return code;
  const faultCode = fault.child('faultcode')?.text.trim() ?? '';
  const local = faultCode.substring(faultCode.indexOf(':') + 1);
  return local === '' ? 'SoapFault' : local;
}

/**
 * Spaces and invisible characters (separators, format characters such as
 * zero-width spaces and soft hyphens, the combining grapheme joiner) at the
 * end of a line, or making up the whole line.
 */
const blankLineEnd = /[\p{Z}\p{Cf}͏\t]+$/gmu;

function sender(item: SoapElement): string {
  const mailbox = item.child('From')?.child('Mailbox');
  const name = mailbox?.child('Name')?.text.trim() ?? '';
  return name !== '' ? name : (mailbox?.child('EmailAddress')?.text.trim() ?? '');
}

const oneLine = (s: string): string => s.replace(/\s+/g, ' ').trim();

/** An xs:dateTime as epoch ms; 0 when missing or unreadable. */
function time(e: SoapElement | null): number {
  const t = Date.parse(e?.text.trim() ?? '');
  return Number.isNaN(t) ? 0 : t;
}

/** An xs:boolean, or null when missing. */
function flag(e: SoapElement | null): boolean | null {
  const v = e?.text.trim().toLowerCase();
  return v === 'true' ? true : v === 'false' ? false : null;
}

function int(e: SoapElement | null): number | null {
  const v = e?.text.trim() ?? '';
  return /^-?\d+$/.test(v) ? Number(v) : null;
}

// ------------------------------------------------------------- XML reader

/**
 * An element from readSoap. Names are matched by local name (prefix dropped)
 * and case-insensitively, so t:Subject, Subject and m:subject all match
 * child('Subject').
 */
export class SoapElement {
  /** As written, e.g. "t:Subject". */
  readonly qualifiedName: string;
  /** Qualified attribute names as written, values with entities decoded. */
  readonly attributes: Record<string, string>;
  readonly content: (string | SoapElement)[] = []; // text or child elements

  constructor(qualifiedName: string, attributes: Record<string, string>) {
    this.qualifiedName = qualifiedName;
    this.attributes = attributes;
  }

  /** "Subject" for "t:Subject". */
  get name(): string {
    return this.qualifiedName.substring(this.qualifiedName.indexOf(':') + 1);
  }

  isNamed(localName: string): boolean {
    return this.name.toLowerCase() === localName.toLowerCase();
  }

  get elements(): SoapElement[] {
    return this.content.filter((c): c is SoapElement => c instanceof SoapElement);
  }

  /** All text inside, entities decoded. */
  get text(): string {
    return this.content.map((c) => (typeof c === 'string' ? c : c.text)).join('');
  }

  /** Attribute by local name, e.g. attr('Id'). */
  attr(localName: string): string | null {
    const want = localName.toLowerCase();
    for (const [k, v] of Object.entries(this.attributes)) {
      if (k.substring(k.indexOf(':') + 1).toLowerCase() === want) return v;
    }
    return null;
  }

  /** First direct child named localName. */
  child(localName: string): SoapElement | null {
    return this.elements.find((e) => e.isNamed(localName)) ?? null;
  }

  /** First descendant named localName, depth first. */
  find(localName: string): SoapElement | null {
    for (const e of this.elements) {
      if (e.isNamed(localName)) return e;
      const hit = e.find(localName);
      if (hit) return hit;
    }
    return null;
  }
}

/**
 * A small non-validating XML reader for SOAP responses. Handles prefixes,
 * self-closing tags, CDATA, comments, processing instructions and the XML
 * entities. Returns a document node whose children are the top-level
 * elements. Throws a SyntaxError on a broken tag.
 */
export function readSoap(xml: string): SoapElement {
  // XML end-of-line handling: literal CR LF and CR read as LF. An escaped
  // &#xD; still decodes to CR.
  xml = xml.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  const document = new SoapElement('#document', {});
  const open = [document];
  const top = () => open[open.length - 1];
  let i = 0;
  while (i < xml.length) {
    const lt = xml.indexOf('<', i);
    if (lt < 0) {
      top().content.push(decode(xml.substring(i)));
      break;
    }
    if (lt > i) top().content.push(decode(xml.substring(i, lt)));

    if (xml.startsWith('<![CDATA[', lt)) {
      const end = indexOf(xml, ']]>', lt + 9);
      top().content.push(xml.substring(lt + 9, end));
      i = end + 3;
    } else if (xml.startsWith('<!--', lt)) {
      i = indexOf(xml, '-->', lt + 4) + 3;
    } else if (xml.startsWith('<?', lt)) {
      i = indexOf(xml, '?>', lt + 2) + 2;
    } else if (xml.startsWith('<!', lt)) {
      i = indexOf(xml, '>', lt + 2) + 1;
    } else if (xml.startsWith('</', lt)) {
      const gt = indexOf(xml, '>', lt + 2);
      const name = xml.substring(lt + 2, gt).trim();
      // Close the matching open element; a stray end tag is ignored.
      let at = -1;
      for (let k = open.length - 1; k >= 0; k--) {
        if (open[k].qualifiedName === name) {
          at = k;
          break;
        }
      }
      if (at > 0) open.length = at;
      i = gt + 1;
    } else {
      startTag.lastIndex = lt;
      const tag = startTag.exec(xml);
      if (!tag) throw new SyntaxError(`Bad start tag at ${lt}`);
      const attributes: Record<string, string> = {};
      for (const a of tag[2].matchAll(attribute)) attributes[a[1]] = decode(a[2] ?? a[3]);
      const element = new SoapElement(tag[1], attributes);
      top().content.push(element);
      if (tag[3] !== '/') open.push(element);
      i = startTag.lastIndex;
    }
  }
  return document;
}

const startTag = /<([^\s/>!?]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>/y;
const attribute = /([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
const entity = /&(#[xX][0-9a-fA-F]+|#[0-9]+|lt|gt|amp|quot|apos);/g;

function indexOf(xml: string, token: string, from: number): number {
  const at = xml.indexOf(token, from);
  if (at < 0) throw new SyntaxError(`Missing ${token} after ${from}`);
  return at;
}

function decode(s: string): string {
  if (!s.includes('&')) return s;
  return s.replace(entity, (whole, e: string) => {
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
    const hex = e[1] === 'x' || e[1] === 'X';
    const code = parseInt(e.substring(hex ? 2 : 1), hex ? 16 : 10);
    if (Number.isNaN(code) || code > 0x10ffff) return whole;
    return String.fromCodePoint(code);
  });
}

// ------------------------------------------- plain-text helpers for the views

/** A link found in plain text: the characters start..end are shown as label and open url. */
export interface FoundLink {
  start: number;
  end: number;
  url: string;
  label: string;
}

const linkPattern =
  /<(?:https?:\/\/|mailto:)[^\s<>"]+>|(?:https?:\/\/|www\.)[^\s<>"']+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+/gi;

/**
 * Web and mail addresses in a plain-text body. Punctuation that ends the
 * sentence is left out of a link, and so is a closing bracket with no opening
 * one inside it.
 *
 * Exchange writes an HTML link as label<url>. Such a bracketed address is
 * shown as its host name only (the label before it already says what it is),
 * so a 300-character tracking URL doesn't bury the message.
 */
export function findLinks(text: string): FoundLink[] {
  const out: FoundLink[] = [];
  const count = (s: string, c: string) => s.split(c).length - 1;
  for (const m of text.matchAll(linkPattern)) {
    const raw = m[0];
    const start = m.index!;
    if (raw.startsWith('<')) {
      const inner = raw.substring(1, raw.length - 1);
      let url: URL;
      try {
        url = new URL(inner);
      } catch {
        continue;
      }
      const isMail = url.protocol.toLowerCase() === 'mailto:';
      if (!isMail && url.host === '') continue;
      const shown = isMail ? decodedPath(url) : url.hostname;
      const spaced = start > 0 && text[start - 1].trim() !== '';
      out.push({ start, end: start + raw.length, url: inner, label: spaced ? ` ${shown}` : shown });
      continue;
    }
    let s = raw;
    while (s.length > 0) {
      const last = s[s.length - 1];
      const unbalanced =
        (last === ')' && count(s, '(') < count(s, ')')) || (last === ']' && count(s, '[') < count(s, ']'));
      if (!`.,;:!?'"`.includes(last) && !unbalanced) break;
      s = s.substring(0, s.length - 1);
    }
    const lower = s.toLowerCase();
    const web = lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('www.');
    let url: string;
    if (web) {
      url = lower.startsWith('www.') ? `https://${s}` : s;
      try {
        if (new URL(url).host === '') continue;
      } catch {
        continue;
      }
    } else {
      url = `mailto:${s}`;
    }
    out.push({ start, end: start + s.length, url, label: s });
  }
  return out;
}

/** A mailto link's address. A stray % leaves it as written: one odd link must not stop the message rendering. */
function decodedPath(url: URL): string {
  try {
    return decodeURIComponent(url.pathname);
  } catch {
    return url.pathname;
  }
}

/** 812 B, 47 KB, 2.3 MB, 18 MB. */
export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${Math.round(kb)} KB`;
  const mb = kb / 1024;
  return mb < 10 ? `${mb.toFixed(1)} MB` : `${Math.round(mb)} MB`;
}

/** The addresses typed into a recipient line: separated by commas, semicolons or new lines; "Name <address>" keeps the address. */
export function parseRecipients(text: string): string[] {
  const out: string[] = [];
  for (const part of text.split(/[,;\n]/)) {
    const p = part.trim();
    if (p === '') continue;
    out.push(/<([^<>]+)>/.exec(p)?.[1]?.trim() ?? p);
  }
  return out;
}

/** Whether a recipient as parsed by parseRecipients looks like an email address. */
export const isEmailAddress = (a: string): boolean => /^[^@\s<>,;]+@[^@\s<>,;]+\.[^@\s<>,;]+$/.test(a);

/** Reply all, as shown before sending: the sender and the To line, then Cc, without the student or repeats. */
export function replyAllRecipients(m: MailMessage): { to: MailAddress[]; cc: MailAddress[] } {
  const me = m.receivedBy.toLowerCase();
  const seen = new Set<string>();
  const keep = (a: MailAddress) => {
    const key = a.address.toLowerCase();
    if (key === '' || key === me || seen.has(key)) return false;
    seen.add(key);
    return true;
  };
  return { to: [{ name: m.from, address: m.fromAddress }, ...m.to].filter(keep), cc: m.cc.filter(keep) };
}

/** The most the composer takes in new files on one message: Exchange's default limit is 35 MB, and base64 adds a third. */
export const maxAttachmentBytes = 25 * 1024 * 1024;

/** What went wrong sending or saving, in one plain sentence (DESIGN.md 10). */
export function composeError(e: unknown, sending: boolean): string {
  const name = (e as { name?: string } | null)?.name;
  if (name === 'LoginRequired') return 'Mail sign-in needed.';
  if (name === 'NetworkError' && !(e as { status?: number }).status) return "Couldn't reach Mail. Check the connection.";
  const message = (e as Error | null)?.message ?? '';
  if (/ErrorInvalidRecipients/.test(message)) return "Mail didn't accept one of the addresses.";
  if (/ErrorMessageSizeExceeded|ErrorAttachmentSizeLimitExceeded|ErrorRequestEntityTooLarge/.test(message)) return 'Mail refused the attachment: it is too big.';
  return sending ? "Mail didn't send it. Try again." : "Mail didn't save the draft. Try again.";
}
