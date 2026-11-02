import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/credentials.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/mail/ews_client.dart';
import 'package:inha_app/services/mail/ews_soap.dart';

import 'ews_test.dart' show FakeCredentials, FakeEws, Reply, Sent, response;

// A rejected password, search, and attachments in and out. Ids are made up.

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

String route(Sent r) {
  if (r.body.contains('<m:FindItem')) return fixture('ews_finditem.xml');
  if (r.body.contains('<m:GetFolder')) return fixture('ews_getfolder.xml');
  if (r.body.contains('<m:CreateItem')) {
    return response('CreateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="d1" ChangeKey="ck1"/></t:Message></m:Items>');
  }
  if (r.body.contains('<m:UpdateItem')) {
    return response('UpdateItem', '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="d1" ChangeKey="ck2"/></t:Message></m:Items>');
  }
  if (r.body.contains('<m:CreateAttachment')) {
    final n = 'ck-file${r.body.contains('second') ? 2 : 1}';
    return response('CreateAttachment', '<m:ResponseCode>NoError</m:ResponseCode><m:Attachments><t:FileAttachment>'
        '<t:AttachmentId Id="a1" RootItemId="d1" RootItemChangeKey="$n"/></t:FileAttachment></m:Attachments>');
  }
  if (r.body.contains('<m:SendItem')) return response('SendItem', '<m:ResponseCode>NoError</m:ResponseCode>');
  throw StateError('unexpected request');
}

(EwsClient, FakeEws, FakeCredentials) make(Reply Function(Sent) handler, {String password = 'secret'}) {
  final fake = FakeEws(handler);
  final creds = FakeCredentials(Credentials('U2310001', password));
  return (EwsClient(Dio()..httpClientAdapter = fake, creds), fake, creds);
}

const pdf = MailFile(name: 'report <1>.pdf', contentType: 'application/pdf', bytes: [1, 2, 3]);
const second = MailFile(name: 'second.txt', contentType: 'text/plain', bytes: [4]);

void main() {
  group('a rejected password', () {
    Reply refuse(Sent r) => (401, '<html>401</html>');

    test('a refresh\'s parallel calls cost one failed logon, not three', () async {
      final (client, fake, _) = make(refuse);
      final results = await Future.wait([
        client.folder(MailFolder.inbox).then<Object?>((v) => v, onError: (Object e) => e),
        client.folderCounts().then<Object?>((v) => v, onError: (Object e) => e),
        client.unreadCount().then<Object?>((v) => v, onError: (Object e) => e),
      ]);
      expect(results, everyElement(isA<LoginRequired>()));
      expect(fake.sent, hasLength(1));
    });

    test('it is not sent again, by this client or the next one (an app restart)', () async {
      final (client, fake, creds) = make(refuse);
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      expect(fake.sent, hasLength(1));

      final next = EwsClient(Dio()..httpClientAdapter = fake, creds);
      await expectLater(next.unreadCount(), throwsA(isA<LoginRequired>()));
      expect(fake.sent, hasLength(1));
    });

    test('saving a login clears it, even the same one again', () async {
      var accept = false;
      final (client, fake, creds) = make((r) => accept ? (200, route(r)) : refuse(r));
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      accept = true;
      await creds.write(Service.mail, const Credentials('U2310001', 'secret'));
      expect(await client.unreadCount(), isA<int>());
      expect(fake.sent, hasLength(2));
    });

    test('a working login is not held up: parallel calls all go out', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      await client.unreadCount(); // now known good
      fake.sent.clear();
      await Future.wait([client.unreadCount(), client.folderCounts(), client.folder(MailFolder.inbox)]);
      expect(fake.sent, hasLength(3));
    });

    test('before that, the others wait for the first answer, then all go', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      await Future.wait([client.unreadCount(), client.folderCounts()]);
      expect(fake.sent, hasLength(2));
    });

    test('a password turned down later is remembered too', () async {
      var accept = true;
      final (client, fake, _) = make((r) => accept ? (200, route(r)) : refuse(r));
      await client.unreadCount();
      accept = false;
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      expect(fake.sent, hasLength(2));
    });

    test('a network failure is not a rejection', () async {
      final (client, fake, _) = make((r) => (503, 'Service Unavailable'));
      await expectLater(client.unreadCount(), throwsA(isA<ParseError>()));
      await expectLater(client.unreadCount(), throwsA(isA<ParseError>()));
      expect(fake.sent, hasLength(2));
    });
  });

  group('search', () {
    test('the query goes last in FindItem, escaped; a folder list has none', () {
      final xml = findItemsEnvelope(folder: MailFolder.sent, query: 'drop & "retake"');
      expect(xml, contains('<m:QueryString>drop &amp; &quot;retake&quot;</m:QueryString>'));
      expect(xml.indexOf('</m:ParentFolderIds>'), lessThan(xml.indexOf('<m:QueryString>')));
      expect(xml, contains('Id="sentitems"'));
      expect(findItemsEnvelope(), isNot(contains('QueryString')));
    });

    test('asks Exchange and reads the answer like any list', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      expect(await client.search(MailFolder.inbox, 'exam', limit: 10, offset: 10), isNotEmpty);
      expect(fake.sent.single.body, contains('<m:QueryString>exam</m:QueryString>'));
      expect(fake.sent.single.body, contains('MaxEntriesReturned="10" Offset="10"'));
    });

    test('nothing to look for asks nothing', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      expect(await client.search(MailFolder.inbox, '   '), isEmpty);
      expect(fake.sent, isEmpty);
    });

    test('a server without Preview still searches', () async {
      final (client, fake, _) =
          make((r) => (200, r.body.contains('item:Preview') ? fixture('ews_finditem_preview_error.xml') : route(r)));
      expect(await client.search(MailFolder.inbox, 'exam'), isNotEmpty);
      expect(fake.sent.last.body, contains('<m:QueryString>exam</m:QueryString>'));
    });
  });

  group('reading attachments', () {
    test('a folder list says which messages have them', () {
      final xml = response(
          'FindItem',
          '<m:RootFolder><t:Items>'
              '<t:Message><t:ItemId Id="a"/><t:HasAttachments>true</t:HasAttachments></t:Message>'
              '<t:Message><t:ItemId Id="b"/><t:HasAttachments>false</t:HasAttachments></t:Message>'
              '<t:Message><t:ItemId Id="c"/></t:Message>'
              '</t:Items></m:RootFolder>');
      expect(parseFindItem(xml).map((h) => h.hasAttachments), [true, false, false]);
      expect(findItemsEnvelope(), contains('<t:FieldURI FieldURI="item:HasAttachments"/>'));
    });

    test('and that survives the cache; an old cache reads as none', () {
      final h = MailHeader(id: 'a', from: 'x', subject: 's', received: DateTime(2026), hasAttachments: true);
      expect(MailHeader.fromJson(h.toJson()).hasAttachments, isTrue);
      expect(h.withUnread(true).hasAttachments, isTrue);
      expect(h.withId('b').hasAttachments, isTrue);
      final old = h.toJson()..remove('hasAttachments');
      expect(MailHeader.fromJson(old).hasAttachments, isFalse);
    });

    test('an opened message gives each file\'s id and type, leaving out inline pictures', () {
      final xml = response(
          'GetItem',
          '<m:Items><t:Message><t:ItemId Id="m1" ChangeKey="k"/><t:Attachments>'
              '<t:FileAttachment><t:AttachmentId Id="att-1"/><t:Name>exam.pdf</t:Name>'
              '<t:ContentType>application/pdf</t:ContentType><t:Size>2048</t:Size><t:IsInline>false</t:IsInline></t:FileAttachment>'
              '<t:FileAttachment><t:AttachmentId Id="att-2"/><t:Name>logo.png</t:Name><t:IsInline>true</t:IsInline></t:FileAttachment>'
              '</t:Attachments></t:Message></m:Items>');
      final a = parseMessage(xml).attachments.single;
      expect((a.id, a.name, a.size, a.contentType), ('att-1', 'exam.pdf', 2048, 'application/pdf'));
    });

    test('a file comes back whole', () async {
      final (client, fake, _) = make((r) => (
            200,
            response(
                'GetAttachment',
                '<m:Attachments><t:FileAttachment><t:Name>exam.pdf</t:Name><t:ContentType>application/pdf</t:ContentType>'
                    '<t:Content>${base64Encode([1, 2, 3])}</t:Content></t:FileAttachment></m:Attachments>')
          ));
      final file = await client.attachment('att&1');
      expect((file.name, file.contentType), ('exam.pdf', 'application/pdf'));
      expect(file.bytes, [1, 2, 3]);
      expect(fake.sent.single.body, contains('<t:AttachmentId Id="att&amp;1"/>'));
    });

    test('an attached message has no file: a ParseError', () {
      final xml = response('GetAttachment', '<m:Attachments><t:ItemAttachment><t:Name>Fwd</t:Name></t:ItemAttachment></m:Attachments>');
      expect(() => parseAttachment(xml), throwsA(isA<ParseError>()));
    });
  });

  group('sending attachments', () {
    String kinds(FakeEws fake) => [
          for (final r in fake.sent)
            RegExp(r'<m:(CreateItem|UpdateItem|CreateAttachment|SendItem)\b').firstMatch(r.body)!.group(1)!,
        ].join(' ');

    test('a new message is saved, given its files, then sent at the newest change key', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      await client.send(const OutgoingMail(ComposeKind.fresh,
          to: ['a@inha.example'], subject: 'Report', body: 'Attached.', attachments: [pdf, second]));
      expect(kinds(fake), 'CreateItem CreateAttachment CreateAttachment SendItem');
      expect(fake.sent[0].body, contains('MessageDisposition="SaveOnly"'));
      expect(fake.sent[1].body, contains('<m:ParentItemId Id="d1" ChangeKey="ck1"/>'));
      expect(fake.sent[1].body, contains('<t:Name>report &lt;1&gt;.pdf</t:Name>'));
      expect(fake.sent[1].body, contains('<t:ContentType>application/pdf</t:ContentType>'));
      expect(fake.sent[1].body, contains('<t:Content>${base64Encode(pdf.bytes)}</t:Content>'));
      expect(fake.sent[2].body, contains('<m:ParentItemId Id="d1" ChangeKey="ck-file1"/>'));
      expect(fake.sent[3].body, contains('<t:ItemId Id="d1" ChangeKey="ck-file2"/>'));
    });

    test('a message with no files still goes straight out', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      await client.send(const OutgoingMail(ComposeKind.fresh, to: ['a@inha.example'], subject: 's', body: 'b'));
      expect(kinds(fake), 'CreateItem');
      expect(fake.sent.single.body, contains('MessageDisposition="SendAndSaveCopy"'));
    });

    test('a reply with files keeps Exchange\'s reply', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      final ref = MailMessage(id: 'o1', changeKey: 'k', from: 'x', subject: 's', received: DateTime(2026), body: '');
      await client.send(OutgoingMail(ComposeKind.reply, ref: ref, body: 'Here.', attachments: const [pdf]));
      expect(kinds(fake), 'CreateItem CreateAttachment SendItem');
      expect(fake.sent[0].body, contains('<t:ReplyToItem>'));
    });

    test('a saved draft: changes, then files, then sent', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      final ref = MailMessage(id: 'd1', changeKey: 'old', from: 'x', subject: 's', received: DateTime(2026), body: '');
      await client.send(OutgoingMail(ComposeKind.draft, ref: ref, subject: 'New', attachments: const [pdf]));
      expect(kinds(fake), 'UpdateItem CreateAttachment SendItem');
      expect(fake.sent[1].body, contains('ChangeKey="ck2"'));
      expect(fake.sent[2].body, contains('ChangeKey="ck-file1"'));
    });

    test('a draft saved with files is not sent', () async {
      final (client, fake, _) = make((r) => (200, route(r)));
      await client.saveDraft(const OutgoingMail(ComposeKind.fresh, subject: 's', attachments: [pdf]));
      expect(kinds(fake), 'CreateItem CreateAttachment');
    });

    test('a file Exchange refuses stops the send; the draft stays in Drafts', () async {
      final (client, fake, _) = make((r) => (
            200,
            r.body.contains('<m:CreateAttachment')
                ? response('CreateAttachment', '<m:ResponseCode>ErrorAttachmentSizeLimitExceeded</m:ResponseCode>',
                    responseClass: 'Error')
                : route(r)
          ));
      await expectLater(client.send(const OutgoingMail(ComposeKind.fresh, subject: 's', attachments: [pdf])),
          throwsA(isA<EwsError>()));
      expect(kinds(fake), 'CreateItem CreateAttachment');
    });

    test('the limit leaves room for base64 under Exchange\'s 35 MB', () {
      expect(maxMailAttachmentBytes * 4 / 3, lessThan(35 * 1024 * 1024));
    });
  });
}
