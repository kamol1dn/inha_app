// Port of test/ews_test.dart and the non-widget parts of
// test/mail_reading_test.dart and test/mail_compose_test.dart. The ids and
// addresses are made up.
import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './setup.ts';
import { LoginRequired, NetworkError, ParseError } from '../src/core/errors.ts';
import type { HttpRequest, HttpResponse } from '../src/core/http.ts';
import type { MailMessage, OutgoingMail } from '../src/core/models.ts';
import { EwsClient, basicAuth, loginCandidates } from '../src/services/mail/ews.ts';
import {
  EwsError,
  createItemEnvelope,
  draftChanges,
  ewsFault,
  ewsMessagesNamespace,
  ewsServerVersion,
  ewsTypesNamespace,
  fileSize,
  findItemsEnvelope,
  findLinks,
  getAttachmentEnvelope,
  getFolderCountsEnvelope,
  getInboxFolderEnvelope,
  getItemEnvelope,
  moveItemEnvelope,
  parseAttachment,
  parseFindItem,
  parseFolderCounts,
  parseGetFolder,
  parseGetItem,
  parseItemId,
  parseMessage,
  parseRecipients,
  parseResolveNames,
  parseUpdateItem,
  previewRejectionCodes,
  readSoap,
  replyAllRecipients,
  resolveNamesEnvelope,
  sendItemEnvelope,
  setReadEnvelope,
  soapNamespace,
  updateDraftEnvelope,
} from '../src/services/mail/soap.ts';

// Item ids from test/fixtures/ews_finditem.xml, newest first.
const ids = [
  'AAMkATDglwkA+hbKMhk0D2CnZBhRk7F0QrkGI6ahdOtMg0+1K0CHzNrWesV2GfVHC2dV+G4Kc+DugAKa3pOdUL3mKfCAqmG/Yb0i/T7cWhc8eCdgARDzxCD9Y+jg8Jf982hElOqf2DC4urFVyAwAAA=',
  'AAMkAtBl/RqtU6aBUwEk3BqjSVh6ewsyHcf6EiwKtq9Qj/TT/6aHDBvY4MDGSl/izPXavYp654YVviL3TwHQVeD7lC/YaBdTqfZprr26n6bc5xfiG6o1xa/FQhf895nyH3facs0Vy/dF97Po0swAAA=',
  'AAMkAfUJlfX1lySUQR/Pp+83/jqLb4YJy/qWUZqzttCaXRybzhAejUrNO4HkISgf47W8m21mKkSUq7C2QMb7xUI+Ykn4E9vKln1eTL6ZbW+tHdusQTgNEKSNXtkJONJnN93eEegJ1syEpxuCUiQAAA=',
  'AAMkA8O0kryfmvqVmKUsNrVmIFVm/lrSdh00yd0ZLAQLZvFaW1053sqyEIRodR7pNlkeJOP0HCCEarc/ZkQq+5xPVB0+x3qgO6yjv0EMeH0Y0gqoNSGtpv5lAk/GM60CUWf89qkXTKe/ju3FpYQAAA=',
  'AAMkAhpzHviWjAUIfgz/P2w/I3Z0+Cv3udgYthgOyr2DeV782bd0lTbyH2JTyFujsCVA8dXVO6xuKpXMgPEDcs3+0/gbczIntv8x/+MC4M+5N+xy4qqmpN/megx/9zfMraRT7d5PF/Eub6MM3ZgAAA=',
];

const getItemBody =
  'Hi all,\n' +
  '\n' +
  'Tomorrow at 15:00 in room B-304 we will go over Lab 3 & the report format.\n' +
  'Bring your laptops; the <dataset> is on eClass.\n' +
  '\n' +
  'Ҳурмат билан,\n' +
  'B. Tursunov';

/** What Exchange sends (HTTP 500) when the request does not validate, e.g. item:Preview against a pre-2013 schema. */
const schemaFault = `
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode xmlns:a="http://schemas.microsoft.com/exchange/services/2006/types">a:ErrorSchemaValidation</faultcode><faultstring xml:lang="en-US">The request failed schema validation: The 'FieldURI' attribute is invalid - The value 'item:Preview' is invalid according to its datatype 'http://schemas.microsoft.com/exchange/services/2006/types:UnindexedFieldURIType' - The Enumeration constraint failed.</faultstring><detail><e:ResponseCode xmlns:e="http://schemas.microsoft.com/exchange/services/2006/errors">ErrorSchemaValidation</e:ResponseCode><e:Message xmlns:e="http://schemas.microsoft.com/exchange/services/2006/errors">The request failed schema validation.</e:Message></detail></s:Fault></s:Body></s:Envelope>
`;

const response = (operation: string, inner: string, responseClass = 'Success') =>
  '<?xml version="1.0" encoding="utf-8"?>' +
  '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>' +
  `<m:${operation}Response xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages" ` +
  'xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"><m:ResponseMessages>' +
  `<m:${operation}ResponseMessage ResponseClass="${responseClass}">${inner}</m:${operation}ResponseMessage>` +
  `</m:ResponseMessages></m:${operation}Response></s:Body></s:Envelope>`;

const itemNotFound = response(
  'GetItem',
  '<m:MessageText>The specified object was not found in the store.</m:MessageText>' +
    '<m:ResponseCode>ErrorItemNotFound</m:ResponseCode>' +
    '<m:DescriptiveLinkKey>0</m:DescriptiveLinkKey><m:Items/>',
  'Error',
);

const original: MailMessage = {
  id: 'orig-1',
  changeKey: 'ck-1',
  from: 'Dilnoza Karimova',
  fromAddress: 'd.karimova@inha.example',
  subject: 'Midterm rooms',
  received: new Date(2026, 9, 23, 9).getTime(),
  unread: false,
  body: 'Rooms are on eClass.',
  attachments: [],
  to: [
    { name: 'Students 2023', address: 'students2023@inha.example' },
    { name: '', address: 'me@student.inha.example' },
  ],
  cc: [
    { name: 'Dean', address: 'dean@inha.example' },
    { name: 'Dilnoza Karimova', address: 'D.Karimova@inha.example' },
  ],
  bcc: [],
  receivedBy: 'me@student.inha.example',
  isDraft: false,
};

const throwsCode = (code: string) => (e: unknown) => e instanceof EwsError && e.code === code;

describe('envelopes', () => {
  test('FindItem: inbox page, IdOnly + seven properties, newest first', () => {
    const xml = findItemsEnvelope();
    assert.ok(xml.startsWith('<?xml version="1.0" encoding="utf-8"?>'));
    assert.ok(xml.includes('<t:RequestServerVersion Version="Exchange2013"/>'));
    assert.ok(xml.includes('<m:FindItem Traversal="Shallow">'));
    assert.ok(xml.includes('<t:BaseShape>IdOnly</t:BaseShape>'));
    for (const f of [
      'item:Subject',
      'message:From',
      'item:DisplayTo',
      'item:DateTimeReceived',
      'message:IsRead',
      'item:HasAttachments',
      'item:Preview',
    ]) {
      assert.ok(xml.includes(`<t:FieldURI FieldURI="${f}"/>`), f);
    }
    assert.ok(xml.includes('<m:IndexedPageItemView MaxEntriesReturned="30" Offset="0" BasePoint="Beginning"/>'));
    assert.ok(xml.includes('<t:FieldOrder Order="Descending">'));
    assert.ok(xml.includes('<t:DistinguishedFolderId Id="inbox"/>'));

    const envelope = readSoap(xml).child('Envelope')!;
    assert.equal(envelope.attributes['xmlns:soap'], soapNamespace);
    assert.equal(envelope.attributes['xmlns:t'], ewsTypesNamespace);
    assert.equal(envelope.attributes['xmlns:m'], ewsMessagesNamespace);
    assert.equal(envelope.find('RequestServerVersion')!.attr('Version'), ewsServerVersion);
    const findItem = envelope.child('Body')!.child('FindItem')!;
    // Schema order of FindItem's children.
    assert.deepEqual(
      findItem.elements.map((e) => e.qualifiedName),
      ['m:ItemShape', 'm:IndexedPageItemView', 'm:SortOrder', 'm:ParentFolderIds'],
    );
    const order = findItem.child('SortOrder')!.child('FieldOrder')!;
    assert.equal(order.attr('Order'), 'Descending');
    assert.equal(order.child('FieldURI')!.attr('FieldURI'), 'item:DateTimeReceived');
  });

  test('FindItem without Preview, with paging and another version', () => {
    const xml = findItemsEnvelope({ limit: 10, offset: 20, withPreview: false, serverVersion: 'Exchange2010_SP2' });
    assert.ok(!xml.includes('item:Preview'));
    assert.ok(xml.includes('<t:FieldURI FieldURI="message:IsRead"/>'));
    assert.ok(xml.includes('MaxEntriesReturned="10" Offset="20"'));
    assert.ok(xml.includes('<t:RequestServerVersion Version="Exchange2010_SP2"/>'));
    assert.equal(readSoap(xml).find('AdditionalProperties')!.elements.length, 6);
  });

  test('FindItem on another folder', () => {
    const xml = findItemsEnvelope({ folder: 'junk' });
    assert.equal(readSoap(xml).find('ParentFolderIds')!.child('DistinguishedFolderId')!.attr('Id'), 'junkemail');
  });

  test('GetItem: header fields, attachments and text body of the exact id', () => {
    const xml = getItemEnvelope(ids[1]);
    assert.ok(xml.includes('<m:GetItem>'));
    assert.ok(xml.includes('<t:BodyType>Text</t:BodyType>'));
    assert.deepEqual(
      readSoap(xml).find('AdditionalProperties')!.elements.map((e) => e.attr('FieldURI')),
      [
        'item:Subject',
        'message:From',
        'item:DateTimeReceived',
        'message:IsRead',
        'item:Attachments',
        'item:Body',
        'message:ToRecipients',
        'message:CcRecipients',
        'message:BccRecipients',
        'message:ReceivedBy',
        'item:IsDraft',
      ],
    );
    assert.ok(xml.includes(`<t:ItemId Id="${ids[1]}"/>`));
    assert.deepEqual(
      readSoap(xml).find('ItemShape')!.elements.map((e) => e.qualifiedName),
      ['t:BaseShape', 't:BodyType', 't:AdditionalProperties'],
    );
  });

  test('GetItem escapes the id', () => {
    const xml = getItemEnvelope('a&b"<c>');
    assert.ok(xml.includes('<t:ItemId Id="a&amp;b&quot;&lt;c&gt;"/>'));
    assert.equal(readSoap(xml).find('ItemId')!.attr('Id'), 'a&b"<c>');
  });

  test('UpdateItem: sets IsRead on the exact id, without a read receipt', () => {
    const update = readSoap(setReadEnvelope(ids[1])).find('UpdateItem')!;
    assert.equal(update.attr('MessageDisposition'), 'SaveOnly');
    assert.equal(update.attr('ConflictResolution'), 'AlwaysOverwrite');
    assert.equal(update.attr('SuppressReadReceipts'), 'true');
    const change = update.find('ItemChange')!;
    assert.equal(change.child('ItemId')!.attr('Id'), ids[1]);
    assert.equal(change.child('ItemId')!.attr('ChangeKey'), null);
    const field = change.find('SetItemField')!;
    assert.equal(field.child('FieldURI')!.attr('FieldURI'), 'message:IsRead');
    assert.equal(field.child('Message')!.child('IsRead')!.text, 'true');

    assert.equal(readSoap(setReadEnvelope('a&b', false)).find('IsRead')!.text, 'false');
    assert.equal(readSoap(setReadEnvelope('a&b')).find('ItemId')!.attr('Id'), 'a&b');
  });

  test('GetFolder: inbox unread count', () => {
    const xml = getInboxFolderEnvelope();
    assert.ok(xml.includes('<t:FieldURI FieldURI="folder:UnreadCount"/>'));
    assert.ok(xml.includes('<t:DistinguishedFolderId Id="inbox"/>'));
    assert.deepEqual(
      readSoap(xml).find('GetFolder')!.elements.map((e) => e.qualifiedName),
      ['m:FolderShape', 'm:FolderIds'],
    );
  });

  test('GetFolder asks for every folder, in the sidebar order', () => {
    const doc = readSoap(getFolderCountsEnvelope());
    assert.deepEqual(
      doc.find('FolderIds')!.elements.map((e) => e.attr('Id')),
      ['inbox', 'drafts', 'sentitems', 'deleteditems', 'junkemail', 'notes'],
    );
    assert.deepEqual(
      doc.find('AdditionalProperties')!.elements.map((e) => e.attr('FieldURI')),
      ['folder:UnreadCount', 'folder:TotalCount'],
    );
  });

  test('a new message: SendAndSaveCopy to Sent, fields in schema order, escaped', () => {
    const xml = createItemEnvelope(
      { kind: 'fresh', to: ['a@x.example'], bcc: ['b@x.example'], subject: 'Q&A', body: 'See <this>' },
      true,
    );
    const create = readSoap(xml).find('CreateItem')!;
    assert.equal(create.attr('MessageDisposition'), 'SendAndSaveCopy');
    assert.equal(create.find('SavedItemFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'sentitems');
    const message = create.find('Items')!.child('Message')!;
    assert.deepEqual(message.elements.map((e) => e.name), ['Subject', 'Body', 'ToRecipients', 'BccRecipients']);
    assert.equal(message.child('Subject')!.text, 'Q&A');
    assert.equal(message.child('Body')!.attr('BodyType'), 'Text');
    assert.equal(message.child('Body')!.text, 'See <this>');
    assert.equal(message.child('ToRecipients')!.find('EmailAddress')!.text, 'a@x.example');
  });

  test('saving a new message puts it in Drafts', () => {
    const create = readSoap(createItemEnvelope({ kind: 'fresh', body: 'x' }, false)).find('CreateItem')!;
    assert.equal(create.attr('MessageDisposition'), 'SaveOnly');
    assert.equal(create.find('SavedItemFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'drafts');
  });

  test('a reply names the original with its change key and leaves recipients to Exchange', () => {
    for (const [kind, tag] of [
      ['reply', 'ReplyToItem'],
      ['replyAll', 'ReplyAllToItem'],
    ] as const) {
      const item = readSoap(createItemEnvelope({ kind, ref: original, body: 'Thanks' }, true)).find('Items')!
        .elements[0];
      assert.equal(item.name, tag);
      assert.deepEqual(item.elements.map((e) => e.name), ['ReferenceItemId', 'NewBodyContent']);
      assert.deepEqual(item.child('ReferenceItemId')!.attributes, { Id: 'orig-1', ChangeKey: 'ck-1' });
      assert.equal(item.child('NewBodyContent')!.attr('BodyType'), 'Text');
      assert.equal(item.child('NewBodyContent')!.text, 'Thanks');
    }
  });

  test('a forward carries its recipients before the reference', () => {
    const item = readSoap(
      createItemEnvelope({ kind: 'forward', ref: original, to: ['a@x.example'], cc: ['c@x.example'], body: '' }, true),
    ).find('ForwardItem')!;
    assert.deepEqual(item.elements.map((e) => e.name), ['ToRecipients', 'CcRecipients', 'ReferenceItemId', 'NewBodyContent']);
  });

  test('a saved draft is updated, not created', () => {
    assert.throws(() => createItemEnvelope({ kind: 'draft', ref: original }, true));
  });

  test('updating a draft writes only what changed; an emptied line is deleted', () => {
    const m: OutgoingMail = { kind: 'draft', ref: original, subject: 'New subject', to: ['a@x.example'], cc: [] };
    assert.equal(draftChanges(m), true);
    assert.equal(draftChanges({ kind: 'draft', ref: original }), false);
    const update = readSoap(updateDraftEnvelope(m)).find('UpdateItem')!;
    assert.equal(update.attr('MessageDisposition'), 'SaveOnly');
    assert.equal(update.find('ItemId')!.attr('Id'), 'orig-1');
    const updates = update.find('Updates')!.elements;
    assert.deepEqual(
      updates.map((e) => `${e.name} ${e.child('FieldURI')!.attr('FieldURI')}`),
      ['SetItemField item:Subject', 'SetItemField message:ToRecipients', 'DeleteItemField message:CcRecipients'],
    );
    assert.equal(updates[0].find('Subject')!.text, 'New subject');
  });

  test('SendItem sends the draft at its change key and keeps a copy in Sent', () => {
    const send = readSoap(sendItemEnvelope('d-1', 'ck-9')).find('SendItem')!;
    assert.equal(send.attr('SaveItemToFolder'), 'true');
    assert.deepEqual(send.find('ItemIds')!.child('ItemId')!.attributes, { Id: 'd-1', ChangeKey: 'ck-9' });
    assert.equal(send.find('SavedItemFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'sentitems');
  });

  test('MoveItem to Deleted', () => {
    const move = readSoap(moveItemEnvelope('x&1', 'deleted')).find('MoveItem')!;
    assert.deepEqual(move.elements.map((e) => e.name), ['ToFolderId', 'ItemIds']);
    assert.equal(move.find('ToFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'deleteditems');
    assert.equal(move.find('ItemId')!.attr('Id'), 'x&1');
  });

  test('ResolveNames searches the directory and contacts without full contact data', () => {
    const resolve = readSoap(resolveNamesEnvelope('Dilnoza')).find('ResolveNames')!;
    assert.equal(resolve.attr('SearchScope'), 'ActiveDirectoryContacts');
    assert.equal(resolve.attr('ReturnFullContactData'), 'false');
    assert.equal(resolve.child('UnresolvedEntry')!.text, 'Dilnoza');
  });

  test('GetAttachment names the attachment, escaped', () => {
    const doc = readSoap(getAttachmentEnvelope('a&1'));
    assert.equal(doc.find('GetAttachment')!.find('AttachmentId')!.attr('Id'), 'a&1');
  });
});

describe('parsers', () => {
  const expectInbox = (inbox: ReturnType<typeof parseFindItem>) => {
    assert.deepEqual(inbox.map((h) => h.id), ids);
    assert.deepEqual(inbox.map((h) => h.from), [
      'Academic Affairs Office',
      'Prof. Bekzod Tursunov',
      'noreply@eclass.inha.example', // no display name: the address
      'Талабалар бўлими',
      'Nodira Karimova',
    ]);
    assert.deepEqual(inbox.map((h) => h.subject), [
      'Midterm exam schedule — Fall 2026',
      'Q&A session: "Deep Learning" <Lab 3> – don\'t miss it',
      '[eClass] New assignment: Multimedia Computing Report 2',
      'Ётоқхона тўлови / Dormitory payment reminder',
      'Capstone meeting: team 7',
    ]);
    assert.deepEqual(inbox.map((h) => h.preview), [
      'Dear students, The midterm exam schedule for Fall 2026 is attached. ' +
        'Please check your room and seat number before Monday.',
      'Hi all, tomorrow at 15:00 in room B-304 we will go over Lab 3 & the report format. Bring your laptops.',
      'Report 2 has been posted. Due: 2 November 2026, 23:59.',
      'Hurmatli talabalar! Ётоқхона тўлови 31 октябргача.',
      'When: Monday, 27 October 2026 14:00-15:00 (UTC+05:00) Tashkent. Where: Library, room 2',
    ]);
    assert.deepEqual(inbox.map((h) => h.received), [
      Date.UTC(2026, 9, 22, 4, 41, 7),
      Date.UTC(2026, 9, 21, 13, 5, 52),
      Date.UTC(2026, 9, 20, 9, 30),
      Date.UTC(2026, 9, 18, 6, 12, 44),
      Date.UTC(2026, 9, 15, 11, 20, 3),
    ]);
    assert.deepEqual(inbox.map((h) => h.unread), [true, true, false, false, true]);
  };

  test('FindItem fixture', () => expectInbox(parseFindItem(fixture('ews_finditem.xml'))));

  test('FindItem on one line, as the server sends it, reads the same', () =>
    expectInbox(parseFindItem(fixture('ews_finditem.xml').replace(/>\s+</g, '><'))));

  test('FindItem with CRLF line endings reads the same', () =>
    expectInbox(parseFindItem(fixture('ews_finditem.xml').replace(/\n/g, '\r\n'))));

  test('FindItem rows carry the To line and the attachment flag', () => {
    const rows = parseFindItem(
      response(
        'FindItem',
        '<m:ResponseCode>NoError</m:ResponseCode><m:RootFolder><t:Items><t:Message>' +
          '<t:ItemId Id="s1"/><t:Subject>Report</t:Subject><t:DisplayTo>Prof. Kim; Lab group</t:DisplayTo>' +
          '<t:HasAttachments>true</t:HasAttachments>' +
          '</t:Message><t:Message><t:ItemId Id="s2"/></t:Message></t:Items></m:RootFolder>',
      ),
    );
    assert.equal(rows[0].to, 'Prof. Kim; Lab group');
    assert.deepEqual(rows.map((r) => r.hasAttachments), [true, false]);
  });

  test('empty inbox', () => {
    const xml = response(
      'FindItem',
      '<m:ResponseCode>NoError</m:ResponseCode><m:RootFolder TotalItemsInView="0" IncludesLastItemInRange="true"><t:Items/></m:RootFolder>',
    );
    assert.deepEqual(parseFindItem(xml), []);
  });

  test('Preview rejected (ResponseClass Error) is an EwsError with its code', () => {
    assert.throws(
      () => parseFindItem(fixture('ews_finditem_preview_error.xml')),
      (e: unknown) =>
        throwsCode('ErrorInvalidPropertyRequest')(e) &&
        (e as Error).message === 'Could not read mail (ErrorInvalidPropertyRequest)' &&
        e instanceof ParseError,
    );
    assert.ok(previewRejectionCodes.has('ErrorInvalidPropertyRequest'));
  });

  test('schema validation SOAP fault is an EwsError with its code', () => {
    assert.throws(() => parseFindItem(schemaFault), throwsCode('ErrorSchemaValidation'));
    assert.equal(ewsFault(schemaFault)!.code, 'ErrorSchemaValidation');
    assert.ok(previewRejectionCodes.has('ErrorSchemaValidation'));
    assert.equal(ewsFault(fixture('ews_finditem.xml')), null);
    assert.equal(ewsFault('<html><body>Service Unavailable</body></html>'), null);
  });

  test('a fault without detail takes the code from faultcode', () => {
    const xml =
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>' +
      '<faultcode xmlns:a="http://schemas.microsoft.com/exchange/services/2006/types">a:ErrorInvalidServerVersion</faultcode>' +
      '<faultstring xml:lang="en-US">The specified server version is invalid.</faultstring>' +
      '</s:Fault></s:Body></s:Envelope>';
    assert.equal(ewsFault(xml)!.code, 'ErrorInvalidServerVersion');
  });

  test('a page that is not SOAP is a plain ParseError', () => {
    const page =
      '<!DOCTYPE html><html><head><title>Outlook</title></head>' +
      '<body><form action="/owa/auth.owa">Sign in</form></body></html>';
    for (const bad of [page, '', '<m:FindItemResponse', '<t:Items x=1>']) {
      assert.throws(
        () => parseFindItem(bad),
        (e: unknown) => e instanceof ParseError && !(e instanceof EwsError),
        bad,
      );
    }
  });

  test('GetItem fixture: plain text with \\n line breaks', () => {
    assert.equal(parseGetItem(fixture('ews_getitem.xml')), getItemBody);
  });

  test('GetItem as a message: sender, subject, time, read flag, file attachments', () => {
    const xml = response(
      'GetItem',
      '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message>' +
        `<t:ItemId Id="${ids[0]}" ChangeKey="CQAAAA"/>` +
        '<t:Subject>Lab 3 report format</t:Subject>' +
        '<t:DateTimeReceived>2026-10-21T09:12:00Z</t:DateTimeReceived>' +
        '<t:Body BodyType="Text">See the template.&#xD;\nThanks</t:Body>' +
        '<t:Attachments>' +
        '<t:FileAttachment><t:AttachmentId Id="a1"/><t:Name>lab3_template.docx</t:Name>' +
        '<t:ContentType>application/vnd.openxmlformats-officedocument.wordprocessingml.document</t:ContentType>' +
        '<t:Size>48213</t:Size><t:IsInline>false</t:IsInline></t:FileAttachment>' +
        '<t:FileAttachment><t:AttachmentId Id="a2"/><t:Name>image001.png</t:Name>' +
        '<t:Size>5120</t:Size><t:IsInline>true</t:IsInline></t:FileAttachment>' +
        '<t:ItemAttachment><t:AttachmentId Id="a3"/><t:Name>Fwd: schedule</t:Name></t:ItemAttachment>' +
        '</t:Attachments>' +
        '<t:From><t:Mailbox><t:Name>Bekzod Tursunov</t:Name>' +
        '<t:EmailAddress>b.tursunov@inha.example</t:EmailAddress></t:Mailbox></t:From>' +
        '<t:IsRead>false</t:IsRead>' +
        '</t:Message></m:Items>',
    );
    const m = parseMessage(xml);
    assert.equal(m.id, ids[0]);
    assert.equal(m.subject, 'Lab 3 report format');
    assert.equal(m.from, 'Bekzod Tursunov');
    assert.equal(m.fromAddress, 'b.tursunov@inha.example');
    assert.equal(m.received, Date.UTC(2026, 9, 21, 9, 12));
    assert.equal(m.unread, true);
    assert.equal(m.body, 'See the template.\nThanks');
    assert.deepEqual(m.attachments, [
      { id: 'a1', name: 'lab3_template.docx', size: 48213 },
      { id: 'a3', name: 'Fwd: schedule', size: 0 },
    ]);
  });

  test('GetItem: change key, recipients, the student and the draft flag', () => {
    const m = parseMessage(
      response(
        'GetItem',
        '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message>' +
          '<t:ItemId Id="i1" ChangeKey="k1"/><t:Subject>Hi</t:Subject>' +
          '<t:ToRecipients><t:Mailbox><t:Name>A</t:Name><t:EmailAddress>a@x.example</t:EmailAddress></t:Mailbox>' +
          '<t:Mailbox><t:EmailAddress>b@x.example</t:EmailAddress></t:Mailbox></t:ToRecipients>' +
          '<t:CcRecipients><t:Mailbox><t:Name>C</t:Name><t:EmailAddress>c@x.example</t:EmailAddress></t:Mailbox></t:CcRecipients>' +
          '<t:IsDraft>true</t:IsDraft>' +
          '<t:ReceivedBy><t:Mailbox><t:Name>Me</t:Name><t:EmailAddress>me@x.example</t:EmailAddress></t:Mailbox></t:ReceivedBy>' +
          '</t:Message></m:Items>',
      ),
    );
    assert.equal(m.changeKey, 'k1');
    assert.deepEqual(m.to.map((a) => a.name || a.address), ['A', 'b@x.example']);
    assert.equal(m.cc[0].address, 'c@x.example');
    assert.deepEqual(m.bcc, []);
    assert.equal(m.receivedBy, 'me@x.example');
    assert.equal(m.isDraft, true);
  });

  test('GetItem body: runs of blank and whitespace-only lines become one blank line', () => {
    const xml = response(
      'GetItem',
      '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="x"/>' +
        '<t:Body BodyType="Text">Dear students,&#xD;\n&#xD;\n  &#xD;\n\t&#xD;\n&#xD;\n' +
        'The exam is on Monday.  &#xD;\n​‌&#xD;\nRoom B-304</t:Body></t:Message></m:Items>',
    );
    assert.equal(parseGetItem(xml), 'Dear students,\n\nThe exam is on Monday.\n\nRoom B-304');
  });

  test('GetItem fixture as a message: no sender fields is not an error', () => {
    const m = parseMessage(fixture('ews_getitem.xml'));
    assert.equal(m.id, ids[1]);
    assert.equal(m.body, getItemBody);
    assert.deepEqual(m.attachments, []);
    assert.equal(m.unread, false);
  });

  test('UpdateItem: success passes, an error carries the ResponseCode', () => {
    parseUpdateItem(response('UpdateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items/>'));
    assert.throws(
      () => parseUpdateItem(response('UpdateItem', '<m:ResponseCode>ErrorAccessDenied</m:ResponseCode>', 'Error')),
      throwsCode('ErrorAccessDenied'),
    );
  });

  test('GetItem error carries the ResponseCode', () => {
    assert.throws(() => parseGetItem(itemNotFound), throwsCode('ErrorItemNotFound'));
  });

  test('GetItem falls back to stripping HTML if the server ignores BodyType', () => {
    const xml = response(
      'GetItem',
      '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="x"/>' +
        '<t:Body BodyType="HTML">&lt;html&gt;&lt;body&gt;&lt;p&gt;Room B-304 &amp;amp; Lab 3&lt;/p&gt;&lt;/body&gt;&lt;/html&gt;</t:Body>' +
        '</t:Message></m:Items>',
    );
    assert.equal(parseGetItem(xml), 'Room B-304 & Lab 3');
  });

  test('GetFolder fixture', () => assert.equal(parseGetFolder(fixture('ews_getfolder.xml')), 12));

  test('folder counts skip a folder the mailbox lacks', () => {
    const folder = (unread: number, total: number) =>
      '<m:ResponseCode>NoError</m:ResponseCode><m:Folders><t:Folder><t:FolderId Id="f"/>' +
      `<t:TotalCount>${total}</t:TotalCount><t:UnreadCount>${unread}</t:UnreadCount></t:Folder></m:Folders>`;
    const ok = '<m:GetFolderResponseMessage ResponseClass="Success">';
    const end = '</m:GetFolderResponseMessage>';
    const xml = response('GetFolder', folder(3, 40)).replace(
      end,
      `${end}${ok}${folder(0, 2)}${end}${ok}${folder(0, 9)}${end}${ok}${folder(1, 5)}${end}` +
        `<m:GetFolderResponseMessage ResponseClass="Error"><m:ResponseCode>ErrorFolderNotFound</m:ResponseCode>${end}` +
        `${ok}${folder(0, 0)}${end}`,
    );
    const counts = parseFolderCounts(xml);
    assert.deepEqual(Object.keys(counts), ['inbox', 'drafts', 'sent', 'deleted', 'notes']);
    assert.equal(counts.inbox!.unread, 3);
    assert.equal(counts.drafts!.total, 2);
  });

  test('item ids from UpdateItem; none from a CreateItem that sent', () => {
    assert.deepEqual(
      parseItemId(
        response(
          'UpdateItem',
          '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="d1" ChangeKey="k2"/></t:Message></m:Items>',
        ),
        'UpdateItem',
      ),
      { id: 'd1', changeKey: 'k2' },
    );
    assert.equal(parseItemId(response('CreateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items/>'), 'CreateItem'), null);
    assert.throws(
      () =>
        parseItemId(response('CreateItem', '<m:ResponseCode>ErrorInvalidRecipients</m:ResponseCode>', 'Error'), 'CreateItem'),
      throwsCode('ErrorInvalidRecipients'),
    );
  });

  test('ResolveNames: several matches, none, and entries without an address', () => {
    const xml = response(
      'ResolveNames',
      '<m:ResponseCode>ErrorNameResolutionMultipleResults</m:ResponseCode>' +
        '<m:ResolutionSet TotalItemsInView="3" IncludesLastItemInRange="true">' +
        '<t:Resolution><t:Mailbox><t:Name>Dilnoza K.</t:Name><t:EmailAddress>d.k@inha.example</t:EmailAddress></t:Mailbox></t:Resolution>' +
        '<t:Resolution><t:Mailbox><t:Name>Dilnoza K.</t:Name><t:EmailAddress>D.K@inha.example</t:EmailAddress></t:Mailbox></t:Resolution>' +
        '<t:Resolution><t:Mailbox><t:Name>Dilnoza R.</t:Name><t:EmailAddress>d.r@student.inha.example</t:EmailAddress></t:Mailbox></t:Resolution>' +
        '<t:Resolution><t:Contact><t:DisplayName>No mail</t:DisplayName></t:Contact></t:Resolution>' +
        '</m:ResolutionSet>',
      'Warning',
    );
    assert.deepEqual(parseResolveNames(xml).map((a) => a.address), ['d.k@inha.example', 'd.r@student.inha.example']);
    assert.deepEqual(
      parseResolveNames(response('ResolveNames', '<m:ResponseCode>ErrorNameResolutionNoResults</m:ResponseCode>', 'Error')),
      [],
    );
  });

  test('GetAttachment: a file, and an attached message that has no file', () => {
    const file = parseAttachment(
      response(
        'GetAttachment',
        '<m:ResponseCode>NoError</m:ResponseCode><m:Attachments><t:FileAttachment><t:AttachmentId Id="a1"/>' +
          '<t:Name>lab3.pdf</t:Name><t:ContentType>application/pdf</t:ContentType>' +
          '<t:Content>JVBERi0x\nLjQK</t:Content></t:FileAttachment></m:Attachments>',
      ),
    );
    assert.deepEqual(file, { name: 'lab3.pdf', contentType: 'application/pdf', base64: 'JVBERi0xLjQK' });
    assert.throws(
      () =>
        parseAttachment(
          response(
            'GetAttachment',
            '<m:ResponseCode>NoError</m:ResponseCode><m:Attachments><t:ItemAttachment><t:Name>Fwd</t:Name></t:ItemAttachment></m:Attachments>',
          ),
        ),
      ParseError,
    );
  });

  test('readSoap: CDATA, comments, entities, quotes, stray end tags', () => {
    const doc = readSoap(
      '<?xml version="1.0"?><!-- c --><a:Root>' +
        "<b x='1' y=\"&lt;2&gt;\">&#x1F4E7; &#65;<![CDATA[<not a tag> &amp;]]></b></stray>" +
        '<c/><D>tail</D></a:Root>',
    );
    const root = doc.child('root')!;
    assert.equal(root.qualifiedName, 'a:Root');
    const b = root.child('B')!;
    assert.equal(b.attr('x'), '1');
    assert.equal(b.attr('Y'), '<2>');
    assert.equal(b.text, '📧 A<not a tag> &amp;');
    assert.deepEqual(root.elements.map((e) => e.name), ['b', 'c', 'D']);
    assert.equal(root.child('c')!.text, '');
    assert.equal(root.child('d')!.text, 'tail');
  });
});

describe('reading and composing helpers', () => {
  const links = (text: string) => findLinks(text).map((l) => [l.label, l.url]);

  test('web addresses, with sentence punctuation left out', () => {
    assert.deepEqual(links('Slides: https://eclass.inha.ac.kr/mod/ubfile/view.php?id=91234. Thanks'), [
      ['https://eclass.inha.ac.kr/mod/ubfile/view.php?id=91234', 'https://eclass.inha.ac.kr/mod/ubfile/view.php?id=91234'],
    ]);
    assert.deepEqual(links('(see https://iut.uz/en/news)'), [['https://iut.uz/en/news', 'https://iut.uz/en/news']]);
    assert.deepEqual(links('Wiki: https://en.wikipedia.org/wiki/JPEG_(format), page 2'), [
      ['https://en.wikipedia.org/wiki/JPEG_(format)', 'https://en.wikipedia.org/wiki/JPEG_(format)'],
    ]);
  });

  test('links Exchange wrote as label<url> show only the host', () => {
    const text = 'Register here<https://forms.office.com/r/abc123?utm_source=x> by Friday';
    const [l] = findLinks(text);
    assert.equal(l.label, ' forms.office.com');
    assert.equal(l.url, 'https://forms.office.com/r/abc123?utm_source=x');
    assert.equal(text.substring(l.start, l.end), '<https://forms.office.com/r/abc123?utm_source=x>');
    assert.deepEqual(links('Write to the office <mailto:registrar@inha.uz>'), [
      ['registrar@inha.uz', 'mailto:registrar@inha.uz'],
    ]);
  });

  test('www. gets https; mail addresses become mailto', () => {
    assert.deepEqual(links('Visit www.inha.uz, or write to registrar@inha.uz.'), [
      ['www.inha.uz', 'https://www.inha.uz'],
      ['registrar@inha.uz', 'mailto:registrar@inha.uz'],
    ]);
  });

  test('plain text has none', () => {
    assert.deepEqual(findLinks('Room B-304 at 15:00. Bring a laptop.'), []);
    assert.deepEqual(findLinks(''), []);
  });

  test('fileSize', () => {
    assert.equal(fileSize(812), '812 B');
    assert.equal(fileSize(48213), '47 KB');
    assert.equal(fileSize(2411724), '2.3 MB');
    assert.equal(fileSize(18874368), '18 MB');
  });

  test('recipient lines split on commas, semicolons and lines; names keep their address', () => {
    assert.deepEqual(parseRecipients(' a@x.example, Prof Kim <kim@x.example>;\nc@x.example ,, '), [
      'a@x.example',
      'kim@x.example',
      'c@x.example',
    ]);
    assert.deepEqual(parseRecipients(''), []);
  });

  test('reply all: sender and To, then Cc, without the student or repeats', () => {
    const r = replyAllRecipients(original);
    assert.deepEqual(r.to.map((a) => a.address), ['d.karimova@inha.example', 'students2023@inha.example']);
    assert.deepEqual(r.cc.map((a) => a.address), ['dean@inha.example']);
  });
});

// ------------------------------------------------------------------ client

interface Sent {
  url: string;
  req: HttpRequest;
  body: string;
  login: string; // the username in the Basic Authorization header
}

type Reply = [status: number, body: string] | Error;

function fakeResponse(url: string, status: number, body: string): HttpResponse {
  const bytes = new TextEncoder().encode(body);
  return {
    status,
    url,
    redirected: false,
    headers: new Headers({ 'Content-Type': status === 200 || status === 500 ? 'text/xml; charset=utf-8' : 'text/html' }),
    bytes,
    text: (encoding = 'utf-8') => new TextDecoder(encoding).decode(bytes),
  };
}

describe('EwsClient', () => {
  const password = 'pa:ss&wörd';
  const login = 'INHA\\U2610999'; // what a saved bare ID is sent as

  const routeOk = (r: Sent) =>
    r.body.includes('<m:FindItem')
      ? fixture('ews_finditem.xml')
      : r.body.includes('<m:GetItem>')
        ? fixture('ews_getitem.xml')
        : r.body.includes('<m:UpdateItem')
          ? response('UpdateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items/>')
          : fixture('ews_getfolder.xml');

  function make(handler: (r: Sent) => Reply, username: string | null = 'U2610999') {
    const sent: Sent[] = [];
    const http = async (url: string, req: HttpRequest = {}): Promise<HttpResponse> => {
      const header = req.headers!.Authorization;
      const decoded = new TextDecoder().decode(
        Uint8Array.from(atob(header.substring('Basic '.length)), (c) => c.charCodeAt(0)),
      );
      const r: Sent = { url, req, body: req.body as string, login: decoded.substring(0, decoded.indexOf(':')) };
      sent.push(r);
      const reply = handler(r);
      if (reply instanceof Error) throw reply;
      return fakeResponse(url, reply[0], reply[1]);
    };
    const creds = async () => (username == null ? null : { username, password });
    return { client: new EwsClient(creds, http), sent };
  }

  test('loginCandidates: a bare ID gets the INHA domain; one form only', () => {
    assert.deepEqual(loginCandidates(' U2610999 '), [login]);
    assert.deepEqual(loginCandidates('OTHER\\U2610999'), ['OTHER\\U2610999']);
    assert.deepEqual(loginCandidates('u@inha.uz'), ['u@inha.uz']);
    assert.deepEqual(loginCandidates('  '), []);
  });

  test('success: SOAP POST with Basic auth; inbox, message, read flag, unread count', async () => {
    const { client, sent } = make((r) => [200, routeOk(r)]);

    const inbox = await client.folder('inbox');
    assert.deepEqual(inbox.map((h) => h.id), ids);
    assert.equal(inbox[2].from, 'noreply@eclass.inha.example');
    assert.equal((await client.message(ids[1])).body, getItemBody);
    assert.equal(await client.unreadCount(), 12);
    await client.markRead(ids[1]);

    assert.equal(sent.length, 4);
    const auth = `Basic ${Buffer.from(`${login}:${password}`, 'utf8').toString('base64')}`;
    assert.equal(basicAuth(login, password), auth);
    for (const r of sent) {
      assert.equal(r.req.method, 'POST');
      assert.equal(r.url, 'https://mail.inha.uz/EWS/Exchange.asmx');
      assert.equal(r.req.headers!['Content-Type'], 'text/xml; charset=utf-8');
      assert.equal(r.req.headers!.Authorization, auth);
      assert.equal(r.req.credentials, 'omit');
      assert.ok(r.body.includes('<t:RequestServerVersion Version="Exchange2013"/>'));
    }
    assert.ok(sent[0].body.includes('item:Preview'));
    assert.ok(sent[1].body.includes(`<t:ItemId Id="${ids[1]}"/>`));
    assert.ok(sent[2].body.includes('folder:UnreadCount'));
    assert.ok(sent[3].body.includes('<m:UpdateItem'));
    assert.ok(sent[3].body.includes('<t:IsRead>true</t:IsRead>'));
  });

  test('401 is LoginRequired for mail, after one attempt only', async () => {
    const { client, sent } = make(() => [401, '<html><body>401 - Unauthorized</body></html>']);
    await assert.rejects(client.folder('inbox'), (e: unknown) => e instanceof LoginRequired && e.service === 'mail');
    // One attempt only: a wrong password must not cost extra failed logons.
    assert.deepEqual(sent.map((r) => r.login), [login]);
  });

  test('no saved login is LoginRequired without a request', async () => {
    const { client, sent } = make((r) => [200, routeOk(r)], null);
    await assert.rejects(client.unreadCount(), (e: unknown) => e instanceof LoginRequired && /No mail login saved/.test((e as Error).message));
    assert.equal(sent.length, 0);
  });

  test('Preview error: retried once without Preview, then never asked again', async () => {
    const previewError = fixture('ews_finditem_preview_error.xml');
    const { client, sent } = make((r) => [200, r.body.includes('item:Preview') ? previewError : routeOk(r)]);

    assert.deepEqual((await client.folder('inbox')).map((h) => h.id), ids);
    assert.equal(sent.length, 2);
    assert.ok(sent[0].body.includes('<t:FieldURI FieldURI="item:Preview"/>'));
    assert.ok(!sent[1].body.includes('item:Preview'));
    assert.ok(sent[1].body.includes('<t:FieldURI FieldURI="message:IsRead"/>'));

    await client.folder('inbox', 30, 30);
    assert.equal(sent.length, 3);
    assert.ok(!sent[2].body.includes('item:Preview'));
    assert.ok(sent[2].body.includes('Offset="30"'));
  });

  test('schema validation fault (HTTP 500 with its body) is retried the same way', async () => {
    const { client, sent } = make((r) => (r.body.includes('item:Preview') ? [500, schemaFault] : [200, routeOk(r)]));
    assert.equal((await client.folder('inbox')).length, 5);
    assert.equal(sent.length, 2);
  });

  test('a 500 that http.ts turned into a NetworkError is retried without Preview too', async () => {
    const { client, sent } = make((r) =>
      r.body.includes('item:Preview') ? new NetworkError('mail.inha.uz answered 500', 500) : [200, routeOk(r)],
    );
    assert.equal((await client.folder('inbox')).length, 5);
    assert.equal(sent.length, 2);
  });

  test('a retry that fails too surfaces the error, without looping', async () => {
    const { client, sent } = make(() => [500, schemaFault]);
    await assert.rejects(client.folder('inbox'), throwsCode('ErrorSchemaValidation'));
    assert.equal(sent.length, 2);
  });

  test('a remembered login that starts failing is LoginRequired after one request', async () => {
    let accept = true;
    const { client, sent } = make((r) => (accept ? [200, routeOk(r)] : [401, '']));
    await client.unreadCount();
    accept = false;
    await assert.rejects(client.unreadCount(), LoginRequired);
    assert.equal(sent.length, 2);
  });

  test('EWS errors are ParseError with the code only, never the password', async () => {
    const { client, sent } = make(() => [200, itemNotFound]);
    const error = await client.message(ids[0]).then(
      () => null,
      (e: unknown) => e,
    );
    assert.ok(error instanceof ParseError);
    assert.equal((error as EwsError).code, 'ErrorItemNotFound');
    assert.equal((error as Error).message, 'Could not read mail (ErrorItemNotFound)');
    assert.ok(!(error as Error).message.includes(password));
    assert.equal(sent.length, 1);
  });

  test('other HTTP statuses are ParseError', async () => {
    const { client } = make(() => [403, '<html><body>Forbidden</body></html>']);
    await assert.rejects(client.unreadCount(), (e: unknown) => e instanceof ParseError && e.what === 'mail (HTTP 403)');
  });

  test('network errors pass through as NetworkError, without the login', async () => {
    const { client } = make(() => new NetworkError('mail.inha.uz unreachable: Failed to fetch'));
    const error = await client.folder('inbox').then(
      () => null,
      (e: unknown) => e,
    );
    assert.ok(error instanceof NetworkError);
    const secret = Buffer.from(`${login}:${password}`, 'utf8').toString('base64');
    assert.ok(!String(error).includes(secret));
    assert.ok(!String(error).includes(password));
  });

  test('sending a saved draft writes the changes, then sends at the new change key', async () => {
    const { client, sent } = make((r) =>
      r.body.includes('<m:UpdateItem')
        ? [200, response('UpdateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="d1" ChangeKey="k2"/></t:Message></m:Items>')]
        : [200, response('SendItem', '<m:ResponseCode>NoError</m:ResponseCode>')],
    );
    await client.send({ kind: 'draft', ref: { id: 'd1', changeKey: 'k1' }, subject: 'Lab 3' });
    assert.equal(sent.length, 2);
    assert.ok(sent[0].body.includes('<m:UpdateItem'));
    assert.deepEqual(readSoap(sent[1].body).find('SendItem')!.find('ItemId')!.attributes, { Id: 'd1', ChangeKey: 'k2' });

    // An unchanged draft is sent as it is, with no update.
    await client.send({ kind: 'draft', ref: { id: 'd1', changeKey: 'k2' } });
    assert.equal(sent.length, 3);
    assert.ok(sent[2].body.includes('<m:SendItem'));
  });

  test('saving an unchanged draft sends nothing; a move returns the new id', async () => {
    const { client, sent } = make(() => [
      200,
      response('MoveItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="moved-1" ChangeKey="k"/></t:Message></m:Items>'),
    ]);
    await client.saveDraft({ kind: 'draft', ref: { id: 'd1', changeKey: 'k1' } });
    assert.equal(sent.length, 0);
    assert.equal(await client.move('id0', 'deleted'), 'moved-1');
    assert.ok(sent[0].body.includes('<t:DistinguishedFolderId Id="deleteditems"/>'));
  });

  test('a reply refused for its addresses carries the code for composeError', async () => {
    const { client } = make(() => [
      200,
      response('CreateItem', '<m:ResponseCode>ErrorInvalidRecipients</m:ResponseCode>', 'Error'),
    ]);
    await assert.rejects(client.send({ kind: 'fresh', to: ['nobody'] }), throwsCode('ErrorInvalidRecipients'));
  });
});
