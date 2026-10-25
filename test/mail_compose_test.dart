import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/features/compose_screen.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/mail/ews_soap.dart';

import 'fakes.dart';

// Folders, sending, replying, drafts, moves and the directory lookup. The
// ids and addresses are made up.

String response(String operation, String inner, {String responseClass = 'Success'}) =>
    '<?xml version="1.0" encoding="utf-8"?>'
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
    '<m:${operation}Response xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages" '
    'xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"><m:ResponseMessages>'
    '<m:${operation}ResponseMessage ResponseClass="$responseClass">$inner</m:${operation}ResponseMessage>'
    '</m:ResponseMessages></m:${operation}Response></s:Body></s:Envelope>';

final original = MailMessage(
  id: 'orig-1',
  changeKey: 'ck-1',
  from: 'Dilnoza Karimova',
  fromAddress: 'd.karimova@inha.example',
  subject: 'Midterm rooms',
  received: DateTime(2026, 10, 23, 9),
  body: 'Rooms are on eClass.',
  to: const [MailAddress('Students 2023', 'students2023@inha.example'), MailAddress('', 'me@student.inha.example')],
  cc: const [MailAddress('Dean', 'dean@inha.example'), MailAddress('Dilnoza Karimova', 'D.Karimova@inha.example')],
  receivedBy: 'me@student.inha.example',
);
void main() {
  group('envelopes', () {
    test('FindItem on another folder', () {
      final xml = findItemsEnvelope(folder: MailFolder.junk);
      expect(readSoap(xml).find('ParentFolderIds')!.child('DistinguishedFolderId')!.attr('Id'), 'junkemail');
    });

    test('GetFolder asks for every folder, in the drawer order', () {
      final doc = readSoap(getFolderCountsEnvelope());
      expect(doc.find('FolderIds')!.elements.map((e) => e.attr('Id')),
          ['inbox', 'drafts', 'sentitems', 'deleteditems', 'junkemail', 'notes']);
      expect(doc.find('AdditionalProperties')!.elements.map((e) => e.attr('FieldURI')),
          ['folder:UnreadCount', 'folder:TotalCount']);
    });

    test('a new message: SendAndSaveCopy to Sent, fields in schema order, escaped', () {
      final xml = createItemEnvelope(
          const OutgoingMail(ComposeKind.fresh,
              to: ['a@x.example'], bcc: ['b@x.example'], subject: 'Q&A', body: 'See <this>'),
          send: true);
      final create = readSoap(xml).find('CreateItem')!;
      expect(create.attr('MessageDisposition'), 'SendAndSaveCopy');
      expect(create.find('SavedItemFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'sentitems');
      final message = create.find('Items')!.child('Message')!;
      expect(message.elements.map((e) => e.name), ['Subject', 'Body', 'ToRecipients', 'BccRecipients']);
      expect(message.child('Subject')!.text, 'Q&A');
      expect(message.child('Body')!.attr('BodyType'), 'Text');
      expect(message.child('Body')!.text, 'See <this>');
      expect(message.child('ToRecipients')!.find('EmailAddress')!.text, 'a@x.example');
    });

    test('saving a new message puts it in Drafts', () {
      final create = readSoap(createItemEnvelope(const OutgoingMail(ComposeKind.fresh, body: 'x'), send: false))
          .find('CreateItem')!;
      expect(create.attr('MessageDisposition'), 'SaveOnly');
      expect(create.find('SavedItemFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'drafts');
    });

    test('a reply names the original with its change key and leaves recipients to Exchange', () {
      for (final (kind, tag) in [(ComposeKind.reply, 'ReplyToItem'), (ComposeKind.replyAll, 'ReplyAllToItem')]) {
        final item = readSoap(createItemEnvelope(OutgoingMail(kind, ref: original, body: 'Thanks'), send: true))
            .find('Items')!
            .elements
            .single;
        expect(item.name, tag);
        expect(item.elements.map((e) => e.name), ['ReferenceItemId', 'NewBodyContent']);
        expect(item.child('ReferenceItemId')!.attributes, {'Id': 'orig-1', 'ChangeKey': 'ck-1'});
        expect(item.child('NewBodyContent')!.attr('BodyType'), 'Text');
        expect(item.child('NewBodyContent')!.text, 'Thanks');
      }
    });

    test('a forward carries its recipients before the reference', () {
      final item = readSoap(createItemEnvelope(
              OutgoingMail(ComposeKind.forward, ref: original, to: const ['a@x.example'], cc: const ['c@x.example'], body: ''),
              send: true))
          .find('ForwardItem')!;
      expect(item.elements.map((e) => e.name), ['ToRecipients', 'CcRecipients', 'ReferenceItemId', 'NewBodyContent']);
    });

    test('a saved draft is updated, not created', () {
      expect(() => createItemEnvelope(OutgoingMail(ComposeKind.draft, ref: original), send: true),
          throwsArgumentError);
    });

    test('updating a draft writes only what changed; an emptied line is deleted', () {
      final m = OutgoingMail(ComposeKind.draft, ref: original, subject: 'New subject', to: const ['a@x.example'], cc: const []);
      expect(draftChanges(m), isTrue);
      expect(draftChanges(OutgoingMail(ComposeKind.draft, ref: original)), isFalse);
      final update = readSoap(updateDraftEnvelope(m)).find('UpdateItem')!;
      expect(update.attr('MessageDisposition'), 'SaveOnly');
      expect(update.find('ItemId')!.attr('Id'), 'orig-1');
      final updates = update.find('Updates')!.elements.toList();
      expect(updates.map((e) => '${e.name} ${e.child('FieldURI')!.attr('FieldURI')}'), [
        'SetItemField item:Subject',
        'SetItemField message:ToRecipients',
        'DeleteItemField message:CcRecipients',
      ]);
      expect(updates.first.find('Subject')!.text, 'New subject');
    });

    test('SendItem sends the draft at its change key and keeps a copy in Sent', () {
      final send = readSoap(sendItemEnvelope('d-1', 'ck-9')).find('SendItem')!;
      expect(send.attr('SaveItemToFolder'), 'true');
      expect(send.find('ItemIds')!.child('ItemId')!.attributes, {'Id': 'd-1', 'ChangeKey': 'ck-9'});
      expect(send.find('SavedItemFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'sentitems');
    });

    test('MoveItem to Deleted', () {
      final move = readSoap(moveItemEnvelope('x&1', MailFolder.deleted)).find('MoveItem')!;
      expect(move.elements.map((e) => e.name), ['ToFolderId', 'ItemIds']);
      expect(move.find('ToFolderId')!.child('DistinguishedFolderId')!.attr('Id'), 'deleteditems');
      expect(move.find('ItemId')!.attr('Id'), 'x&1');
    });

    test('ResolveNames searches the directory and contacts without full contact data', () {
      final resolve = readSoap(resolveNamesEnvelope('Dilnoza')).find('ResolveNames')!;
      expect(resolve.attr('SearchScope'), 'ActiveDirectoryContacts');
      expect(resolve.attr('ReturnFullContactData'), 'false');
      expect(resolve.child('UnresolvedEntry')!.text, 'Dilnoza');
    });
  });

  group('parsers', () {
    test('GetItem: change key, recipients, the student and the draft flag', () {
      final m = parseMessage(response(
          'GetItem',
          '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message>'
              '<t:ItemId Id="i1" ChangeKey="k1"/><t:Subject>Hi</t:Subject>'
              '<t:ToRecipients><t:Mailbox><t:Name>A</t:Name><t:EmailAddress>a@x.example</t:EmailAddress></t:Mailbox>'
              '<t:Mailbox><t:EmailAddress>b@x.example</t:EmailAddress></t:Mailbox></t:ToRecipients>'
              '<t:CcRecipients><t:Mailbox><t:Name>C</t:Name><t:EmailAddress>c@x.example</t:EmailAddress></t:Mailbox></t:CcRecipients>'
              '<t:IsDraft>true</t:IsDraft>'
              '<t:ReceivedBy><t:Mailbox><t:Name>Me</t:Name><t:EmailAddress>me@x.example</t:EmailAddress></t:Mailbox></t:ReceivedBy>'
              '</t:Message></m:Items>'));
      expect(m.changeKey, 'k1');
      expect(m.to.map((a) => a.label), ['A', 'b@x.example']);
      expect(m.cc.single.address, 'c@x.example');
      expect(m.bcc, isEmpty);
      expect(m.receivedBy, 'me@x.example');
      expect(m.isDraft, isTrue);
    });

    test('FindItem rows carry the To line', () {
      final rows = parseFindItem(response(
          'FindItem',
          '<m:ResponseCode>NoError</m:ResponseCode><m:RootFolder><t:Items><t:Message>'
              '<t:ItemId Id="s1"/><t:Subject>Report</t:Subject><t:DisplayTo>Prof. Kim; Lab group</t:DisplayTo>'
              '</t:Message></t:Items></m:RootFolder>'));
      expect(rows.single.to, 'Prof. Kim; Lab group');
    });

    test('folder counts skip a folder the mailbox lacks', () {
      String folder(int unread, int total) =>
          '<m:ResponseCode>NoError</m:ResponseCode><m:Folders><t:Folder><t:FolderId Id="f"/>'
          '<t:TotalCount>$total</t:TotalCount><t:UnreadCount>$unread</t:UnreadCount></t:Folder></m:Folders>';
      const ok = '<m:GetFolderResponseMessage ResponseClass="Success">';
      const end = '</m:GetFolderResponseMessage>';
      final xml = response('GetFolder', folder(3, 40)).replaceFirst(
          end,
          '$end$ok${folder(0, 2)}$end$ok${folder(0, 9)}$end$ok${folder(1, 5)}$end'
          '<m:GetFolderResponseMessage ResponseClass="Error"><m:ResponseCode>ErrorFolderNotFound</m:ResponseCode>$end'
          '$ok${folder(0, 0)}$end');
      final counts = parseFolderCounts(xml);
      expect(counts.keys, [MailFolder.inbox, MailFolder.drafts, MailFolder.sent, MailFolder.deleted, MailFolder.notes]);
      expect(counts[MailFolder.inbox]!.unread, 3);
      expect(counts[MailFolder.drafts]!.total, 2);
    });

    test('item ids from UpdateItem; none from a CreateItem that sent', () {
      expect(
          parseItemId(
              response('UpdateItem',
                  '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="d1" ChangeKey="k2"/></t:Message></m:Items>'),
              'UpdateItem'),
          ('d1', 'k2'));
      expect(parseItemId(response('CreateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items/>'), 'CreateItem'),
          isNull);
      expect(
          () => parseItemId(
              response('CreateItem', '<m:ResponseCode>ErrorInvalidRecipients</m:ResponseCode>', responseClass: 'Error'),
              'CreateItem'),
          throwsA(isA<EwsError>().having((e) => e.code, 'code', 'ErrorInvalidRecipients')));
    });

    test('ResolveNames: several matches, none, and entries without an address', () {
      final xml = response(
          'ResolveNames',
          '<m:ResponseCode>ErrorNameResolutionMultipleResults</m:ResponseCode>'
              '<m:ResolutionSet TotalItemsInView="3" IncludesLastItemInRange="true">'
              '<t:Resolution><t:Mailbox><t:Name>Dilnoza K.</t:Name><t:EmailAddress>d.k@inha.example</t:EmailAddress></t:Mailbox></t:Resolution>'
              '<t:Resolution><t:Mailbox><t:Name>Dilnoza K.</t:Name><t:EmailAddress>D.K@inha.example</t:EmailAddress></t:Mailbox></t:Resolution>'
              '<t:Resolution><t:Mailbox><t:Name>Dilnoza R.</t:Name><t:EmailAddress>d.r@student.inha.example</t:EmailAddress></t:Mailbox></t:Resolution>'
              '<t:Resolution><t:Contact><t:DisplayName>No mail</t:DisplayName></t:Contact></t:Resolution>'
              '</m:ResolutionSet>',
          responseClass: 'Warning');
      expect(parseResolveNames(xml).map((a) => a.address), ['d.k@inha.example', 'd.r@student.inha.example']);
      expect(
          parseResolveNames(response('ResolveNames', '<m:ResponseCode>ErrorNameResolutionNoResults</m:ResponseCode>',
              responseClass: 'Error')),
          isEmpty);
    });
  });

  group('composer', () {
    test('recipient lines split on commas, semicolons and lines; names keep their address', () {
      expect(parseRecipients(' a@x.example, Prof Kim <kim@x.example>;\nc@x.example ,, '),
          ['a@x.example', 'kim@x.example', 'c@x.example']);
      expect(parseRecipients(''), isEmpty);
    });

    test('reply all: sender and To, then Cc, without the student or repeats', () {
      final r = replyAllRecipients(original);
      expect(r.to.map((a) => a.address), ['d.karimova@inha.example', 'students2023@inha.example']);
      expect(r.cc.map((a) => a.address), ['dean@inha.example']);
    });
  });

  group('AppData', () {
    test('a folder loads on its own and is cached under its own key', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.folders[MailFolder.sent] = [mailHeader(1)];
      mail.counts = {MailFolder.drafts: const MailFolderCount(0, 2)};
      await data.refreshMail(folder: MailFolder.sent);
      expect(data.mailbox(MailFolder.sent).list.data!.value.single.id, 'id1');
      expect(data.inbox.data, isNull);
      expect(data.mailCounts[MailFolder.drafts]!.total, 2);
      await data.reloadFromCache();
      expect(data.mailbox(MailFolder.sent).list.data!.value.single.id, 'id1');
    });

    test('deleting moves to Deleted, leaves the list and the unread count, and can be undone', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [mailHeader(0, unread: true), mailHeader(1)];
      mail.unread = 1;
      await data.refreshMail();
      final moved = await data.moveMail(data.inbox.data!.value.first, from: MailFolder.inbox, to: MailFolder.deleted);
      expect(mail.moves, [('id0', MailFolder.deleted)]);
      expect(data.inbox.data!.value.map((m) => m.id), ['id1']);
      expect(data.mailUnread.data!.value, 0);
      expect(moved!.id, 'moved-id0');
      await data.moveMail(moved, from: MailFolder.deleted, to: MailFolder.inbox);
      expect(mail.moves.last, ('moved-id0', MailFolder.inbox));
      expect(data.mailUnread.data!.value, 1);
    });

    test('a sent draft leaves Drafts', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.folders[MailFolder.drafts] = [mailHeader(4)];
      await data.refreshMailFolder(MailFolder.drafts);
      final draft = MailMessage(id: 'id4', from: '', subject: '', received: DateTime(2026), body: '');
      await data.sendMail(OutgoingMail(ComposeKind.draft, ref: draft));
      expect(mail.sent.single.kind, ComposeKind.draft);
      expect(data.mailbox(MailFolder.drafts).list.data!.value, isEmpty);
    });

    test('a failed send changes nothing here', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.error = Exception('offline');
      await expectLater(data.sendMail(const OutgoingMail(ComposeKind.fresh, to: ['a@x.example'])), throwsException);
      expect(mail.sent, isEmpty);
    });

    test('a signed-out folder keeps its error when the app comes back', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.error = LoginRequired(Service.mail);
      await data.refreshMail();
      await data.reloadFromCache();
      expect(data.inbox.error, isA<LoginRequired>());
      expect(data.mailUnread.error, isA<LoginRequired>());
    });

    test('signing out forgets every folder', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.folders[MailFolder.junk] = [mailHeader(2)];
      await data.refreshMail(folder: MailFolder.junk);
      await data.forget(Service.mail);
      expect(data.mailbox(MailFolder.junk).list.data, isNull);
      await data.reloadFromCache();
      expect(data.mailbox(MailFolder.junk).list.data, isNull);
    });
  });

  test('page size is shared by every folder', () => expect(AppData.mailPageSize, 30));
}
