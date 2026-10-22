import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/credentials.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/mail/ews_client.dart';
import 'package:inha_app/services/mail/ews_soap.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

// Item ids from test/fixtures/ews_finditem.xml, newest first.
const ids = [
  'AAMkATDglwkA+hbKMhk0D2CnZBhRk7F0QrkGI6ahdOtMg0+1K0CHzNrWesV2GfVHC2dV+G4Kc+DugAKa3pOdUL3mKfCAqmG/Yb0i/T7cWhc8eCdgARDzxCD9Y+jg8Jf982hElOqf2DC4urFVyAwAAA=',
  'AAMkAtBl/RqtU6aBUwEk3BqjSVh6ewsyHcf6EiwKtq9Qj/TT/6aHDBvY4MDGSl/izPXavYp654YVviL3TwHQVeD7lC/YaBdTqfZprr26n6bc5xfiG6o1xa/FQhf895nyH3facs0Vy/dF97Po0swAAA=',
  'AAMkAfUJlfX1lySUQR/Pp+83/jqLb4YJy/qWUZqzttCaXRybzhAejUrNO4HkISgf47W8m21mKkSUq7C2QMb7xUI+Ykn4E9vKln1eTL6ZbW+tHdusQTgNEKSNXtkJONJnN93eEegJ1syEpxuCUiQAAA=',
  'AAMkA8O0kryfmvqVmKUsNrVmIFVm/lrSdh00yd0ZLAQLZvFaW1053sqyEIRodR7pNlkeJOP0HCCEarc/ZkQq+5xPVB0+x3qgO6yjv0EMeH0Y0gqoNSGtpv5lAk/GM60CUWf89qkXTKe/ju3FpYQAAA=',
  'AAMkAhpzHviWjAUIfgz/P2w/I3Z0+Cv3udgYthgOyr2DeV782bd0lTbyH2JTyFujsCVA8dXVO6xuKpXMgPEDcs3+0/gbczIntv8x/+MC4M+5N+xy4qqmpN/megx/9zfMraRT7d5PF/Eub6MM3ZgAAA=',
];

const getItemBody = 'Hi all,\n'
    '\n'
    'Tomorrow at 15:00 in room B-304 we will go over Lab 3 & the report format.\n'
    'Bring your laptops; the <dataset> is on eClass.\n'
    '\n'
    'Ҳурмат билан,\n'
    'B. Tursunov';

/// What Exchange sends (HTTP 500) when the request does not validate, e.g.
/// item:Preview against a pre-2013 schema.
const schemaFault = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><faultcode xmlns:a="http://schemas.microsoft.com/exchange/services/2006/types">a:ErrorSchemaValidation</faultcode><faultstring xml:lang="en-US">The request failed schema validation: The 'FieldURI' attribute is invalid - The value 'item:Preview' is invalid according to its datatype 'http://schemas.microsoft.com/exchange/services/2006/types:UnindexedFieldURIType' - The Enumeration constraint failed.</faultstring><detail><e:ResponseCode xmlns:e="http://schemas.microsoft.com/exchange/services/2006/errors">ErrorSchemaValidation</e:ResponseCode><e:Message xmlns:e="http://schemas.microsoft.com/exchange/services/2006/errors">The request failed schema validation.</e:Message><t:MessageXml xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"><t:LineNumber>1</t:LineNumber><t:LinePosition>812</t:LinePosition><t:Violation>The 'FieldURI' attribute is invalid - The value 'item:Preview' is invalid according to its datatype 'http://schemas.microsoft.com/exchange/services/2006/types:UnindexedFieldURIType' - The Enumeration constraint failed.</t:Violation></t:MessageXml></detail></s:Fault></s:Body></s:Envelope>
''';

String response(String operation, String inner, {String responseClass = 'Success'}) => '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><m:${operation}Response xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages" xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"><m:ResponseMessages><m:${operation}ResponseMessage ResponseClass="$responseClass">$inner</m:${operation}ResponseMessage></m:ResponseMessages></m:${operation}Response></s:Body></s:Envelope>
''';

final itemNotFound = response(
  'GetItem',
  '<m:MessageText>The specified object was not found in the store.</m:MessageText>'
      '<m:ResponseCode>ErrorItemNotFound</m:ResponseCode>'
      '<m:DescriptiveLinkKey>0</m:DescriptiveLinkKey><m:Items/>',
  responseClass: 'Error',
);

void main() {
  group('envelopes', () {
    test('FindItem: inbox page, IdOnly + five properties, newest first', () {
      final xml = findInboxEnvelope();
      expect(xml, startsWith('<?xml version="1.0" encoding="utf-8"?>'));
      expect(xml, contains('<t:RequestServerVersion Version="Exchange2013"/>'));
      expect(xml, contains('<m:FindItem Traversal="Shallow">'));
      expect(xml, contains('<t:BaseShape>IdOnly</t:BaseShape>'));
      for (final f in [
        'item:Subject',
        'message:From',
        'item:DateTimeReceived',
        'message:IsRead',
        'item:Preview',
      ]) {
        expect(xml, contains('<t:FieldURI FieldURI="$f"/>'));
      }
      expect(xml,
          contains('<m:IndexedPageItemView MaxEntriesReturned="30" Offset="0" BasePoint="Beginning"/>'));
      expect(xml, contains('<t:FieldOrder Order="Descending">'));
      expect(xml, contains('<t:DistinguishedFolderId Id="inbox"/>'));

      final doc = readSoap(xml);
      final envelope = doc.child('Envelope')!;
      expect(envelope.attributes['xmlns:soap'], soapNamespace);
      expect(envelope.attributes['xmlns:t'], ewsTypesNamespace);
      expect(envelope.attributes['xmlns:m'], ewsMessagesNamespace);
      expect(envelope.find('RequestServerVersion')!.attr('Version'), ewsServerVersion);
      final findItem = envelope.child('Body')!.child('FindItem')!;
      // Schema order of FindItem's children.
      expect(findItem.elements.map((e) => e.qualifiedName),
          ['m:ItemShape', 'm:IndexedPageItemView', 'm:SortOrder', 'm:ParentFolderIds']);
      final order = findItem.child('SortOrder')!.child('FieldOrder')!;
      expect(order.attr('Order'), 'Descending');
      expect(order.child('FieldURI')!.attr('FieldURI'), 'item:DateTimeReceived');
    });

    test('FindItem without Preview, with paging and another version', () {
      final xml = findInboxEnvelope(
          limit: 10, offset: 20, withPreview: false, serverVersion: 'Exchange2010_SP2');
      expect(xml, isNot(contains('item:Preview')));
      expect(xml, contains('<t:FieldURI FieldURI="message:IsRead"/>'));
      expect(xml, contains('MaxEntriesReturned="10" Offset="20"'));
      expect(xml, contains('<t:RequestServerVersion Version="Exchange2010_SP2"/>'));
      expect(readSoap(xml).find('AdditionalProperties')!.elements, hasLength(4));
    });

    test('GetItem: text body of the exact id', () {
      final xml = getItemEnvelope(ids[1]);
      expect(xml, contains('<t:RequestServerVersion Version="Exchange2013"/>'));
      expect(xml, contains('<m:GetItem>'));
      expect(xml, contains('<t:BodyType>Text</t:BodyType>'));
      expect(xml, contains('<t:FieldURI FieldURI="item:Body"/>'));
      expect(xml, contains('<t:ItemId Id="${ids[1]}"/>'));
      final shape = readSoap(xml).find('ItemShape')!;
      expect(shape.elements.map((e) => e.qualifiedName),
          ['t:BaseShape', 't:BodyType', 't:AdditionalProperties']);
    });

    test('GetItem escapes the id', () {
      final xml = getItemEnvelope('a&b"<c>');
      expect(xml, contains('<t:ItemId Id="a&amp;b&quot;&lt;c&gt;"/>'));
      expect(readSoap(xml).find('ItemId')!.attr('Id'), 'a&b"<c>');
    });

    test('GetFolder: inbox unread count', () {
      final xml = getInboxFolderEnvelope();
      expect(xml, contains('<t:RequestServerVersion Version="Exchange2013"/>'));
      expect(xml, contains('<m:GetFolder>'));
      expect(xml, contains('<t:FieldURI FieldURI="folder:UnreadCount"/>'));
      expect(xml, contains('<t:DistinguishedFolderId Id="inbox"/>'));
      expect(readSoap(xml).find('GetFolder')!.elements.map((e) => e.qualifiedName),
          ['m:FolderShape', 'm:FolderIds']);
    });
  });

  group('parsers', () {
    void expectInbox(List<MailHeader> inbox) {
      expect(inbox.map((h) => h.id), ids);
      expect(inbox.map((h) => h.from), [
        'Academic Affairs Office',
        'Prof. Bekzod Tursunov',
        'noreply@eclass.inha.example', // no display name: the address
        'Талабалар бўлими',
        'Nodira Karimova',
      ]);
      expect(inbox.map((h) => h.subject), [
        'Midterm exam schedule — Fall 2026',
        'Q&A session: "Deep Learning" <Lab 3> – don\'t miss it',
        '[eClass] New assignment: Multimedia Computing Report 2',
        'Ётоқхона тўлови / Dormitory payment reminder',
        'Capstone meeting: team 7',
      ]);
      expect(inbox.map((h) => h.preview), [
        'Dear students, The midterm exam schedule for Fall 2026 is attached. '
            'Please check your room and seat number before Monday.',
        'Hi all, tomorrow at 15:00 in room B-304 we will go over Lab 3 & the report format. '
            'Bring your laptops.',
        'Report 2 has been posted. Due: 2 November 2026, 23:59.',
        'Hurmatli talabalar! Ётоқхона тўлови 31 октябргача.',
        'When: Monday, 27 October 2026 14:00-15:00 (UTC+05:00) Tashkent. Where: Library, room 2',
      ]);
      expect(inbox.map((h) => h.received.toUtc()), [
        DateTime.utc(2026, 10, 22, 4, 41, 7),
        DateTime.utc(2026, 10, 21, 13, 5, 52),
        DateTime.utc(2026, 10, 20, 9, 30),
        DateTime.utc(2026, 10, 18, 6, 12, 44),
        DateTime.utc(2026, 10, 15, 11, 20, 3),
      ]);
      expect(inbox.every((h) => !h.received.isUtc), isTrue, reason: 'local time for display');
      expect(inbox.map((h) => h.unread), [true, true, false, false, true]);
    }

    test('FindItem fixture', () {
      expectInbox(parseFindItem(fixture('ews_finditem.xml')));
    });

    test('FindItem on one line, as the server sends it, reads the same', () {
      final compact = fixture('ews_finditem.xml').replaceAll(RegExp(r'>\s+<'), '><');
      expectInbox(parseFindItem(compact));
    });

    test('FindItem with CRLF line endings reads the same', () {
      expectInbox(parseFindItem(fixture('ews_finditem.xml').replaceAll('\n', '\r\n')));
    });

    test('empty inbox', () {
      final xml = response('FindItem',
          '<m:ResponseCode>NoError</m:ResponseCode><m:RootFolder TotalItemsInView="0" IncludesLastItemInRange="true"><t:Items/></m:RootFolder>');
      expect(parseFindItem(xml), isEmpty);
    });

    test('Preview rejected (ResponseClass Error) is an EwsError with its code', () {
      expect(
        () => parseFindItem(fixture('ews_finditem_preview_error.xml')),
        throwsA(isA<EwsError>()
            .having((e) => e.code, 'code', 'ErrorInvalidPropertyRequest')
            .having((e) => e.toString(), 'toString', 'Could not read mail (ErrorInvalidPropertyRequest)')),
      );
      expect(previewRejectionCodes, contains('ErrorInvalidPropertyRequest'));
    });

    test('schema validation SOAP fault is an EwsError with its code', () {
      expect(() => parseFindItem(schemaFault),
          throwsA(isA<EwsError>().having((e) => e.code, 'code', 'ErrorSchemaValidation')));
      expect(ewsFault(schemaFault)!.code, 'ErrorSchemaValidation');
      expect(previewRejectionCodes, contains('ErrorSchemaValidation'));
      expect(ewsFault(fixture('ews_finditem.xml')), isNull);
      expect(ewsFault('<html><body>Service Unavailable</body></html>'), isNull);
    });

    test('a fault without detail takes the code from faultcode', () {
      const xml = '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>'
          '<faultcode xmlns:a="http://schemas.microsoft.com/exchange/services/2006/types">a:ErrorInvalidServerVersion</faultcode>'
          '<faultstring xml:lang="en-US">The specified server version is invalid.</faultstring>'
          '</s:Fault></s:Body></s:Envelope>';
      expect(ewsFault(xml)!.code, 'ErrorInvalidServerVersion');
    });

    test('a page that is not SOAP is a plain ParseError', () {
      const page = '<!DOCTYPE html><html><head><title>Outlook</title></head>'
          '<body><form action="/owa/auth.owa">Sign in</form></body></html>';
      for (final bad in [page, '', '<m:FindItemResponse', '<t:Items x=1>']) {
        expect(() => parseFindItem(bad),
            throwsA(isA<ParseError>().having((e) => e is EwsError, 'is EwsError', isFalse)));
      }
    });

    test('GetItem fixture: plain text with \\n line breaks', () {
      expect(parseGetItem(fixture('ews_getitem.xml')), getItemBody);
    });

    test('GetItem error carries the ResponseCode', () {
      expect(() => parseGetItem(itemNotFound),
          throwsA(isA<EwsError>().having((e) => e.code, 'code', 'ErrorItemNotFound')));
    });

    test('GetItem falls back to stripping HTML if the server ignores BodyType', () {
      final xml = response('GetItem',
          '<m:ResponseCode>NoError</m:ResponseCode><m:Items><t:Message><t:ItemId Id="x"/>'
          '<t:Body BodyType="HTML">&lt;html&gt;&lt;body&gt;&lt;p&gt;Room B-304 &amp;amp; Lab 3&lt;/p&gt;&lt;/body&gt;&lt;/html&gt;</t:Body>'
          '</t:Message></m:Items>');
      expect(parseGetItem(xml), 'Room B-304 & Lab 3');
    });

    test('GetFolder fixture', () {
      expect(parseGetFolder(fixture('ews_getfolder.xml')), 12);
    });

    test('readSoap: CDATA, comments, entities, quotes, stray end tags', () {
      final doc = readSoap('<?xml version="1.0"?><!-- c --><a:Root>'
          "<b x='1' y=\"&lt;2&gt;\">&#x1F4E7; &#65;<![CDATA[<not a tag> &amp;]]></b></stray>"
          '<c/><D>tail</D></a:Root>');
      final root = doc.child('root')!;
      expect(root.qualifiedName, 'a:Root');
      final b = root.child('B')!;
      expect(b.attr('x'), '1');
      expect(b.attr('Y'), '<2>');
      expect(b.text, '📧 A<not a tag> &amp;');
      expect(root.elements.map((e) => e.name), ['b', 'c', 'D']);
      expect(root.child('c')!.text, '');
      expect(root.child('d')!.text, 'tail');
    });
  });

  group('EwsClient', () {
    const password = 'pa:ss&wörd';
    const login = 'INHA' r'\' 'U2610999'; // what a saved bare ID is sent as

    String routeOk(Sent r) => r.body.contains('<m:FindItem')
        ? fixture('ews_finditem.xml')
        : r.body.contains('<m:GetItem>')
            ? fixture('ews_getitem.xml')
            : fixture('ews_getfolder.xml');

    (EwsClient, FakeEws) make(Reply Function(Sent) handler,
        {String? username = 'U2610999'}) {
      final fake = FakeEws(handler);
      final dio = Dio()..httpClientAdapter = fake;
      final store = FakeCredentials(username == null ? null : Credentials(username, password));
      return (EwsClient(dio, store), fake);
    }

    test('loginCandidates: a bare ID gets the INHA domain; one form only', () {
      expect(EwsClient.loginCandidates(' U2610999 '), [login]);
      const otherDomain = 'OTHER' r'\' 'U2610999'; // DOMAIN\user, sent as is
      expect(EwsClient.loginCandidates(otherDomain), [otherDomain]);
      expect(EwsClient.loginCandidates('u@inha.uz'), ['u@inha.uz']);
      expect(EwsClient.loginCandidates('  '), isEmpty);
    });

    test('success: SOAP POST with Basic auth; inbox, body and unread count', () async {
      final (client, fake) = make((r) => (200, routeOk(r)));

      final inbox = await client.inbox();
      expect(inbox.map((h) => h.id), ids);
      expect(inbox[2].from, 'noreply@eclass.inha.example');
      expect(await client.body(ids[1]), getItemBody);
      expect(await client.unreadCount(), 12);

      expect(fake.sent, hasLength(3));
      final auth = 'Basic ${base64Encode(utf8.encode('$login:$password'))}';
      for (final r in fake.sent) {
        expect(r.options.method, 'POST');
        expect(r.options.uri.toString(), 'https://mail.inha.uz/EWS/Exchange.asmx');
        expect(r.options.contentType, 'text/xml; charset=utf-8');
        expect(r.options.headers['Authorization'], auth);
        expect(r.body, contains('<t:RequestServerVersion Version="Exchange2013"/>'));
      }
      expect(fake.sent[0].body, contains('item:Preview'));
      expect(fake.sent[1].body, contains('<t:ItemId Id="${ids[1]}"/>'));
      expect(fake.sent[2].body, contains('folder:UnreadCount'));
    });

    test('401 is LoginRequired(Service.mail)', () async {
      final (client, fake) = make((r) => (401, '<html><body>401 - Unauthorized</body></html>'));
      await expectLater(client.inbox(),
          throwsA(isA<LoginRequired>().having((e) => e.service, 'service', Service.mail)));
      // One attempt only: a wrong password must not cost extra failed logons.
      expect(fake.sent.map((r) => r.login), [login]);
    });

    test('no saved login is LoginRequired without a request', () async {
      final (client, fake) = make((r) => (200, routeOk(r)), username: null);
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      expect(fake.sent, isEmpty);
    });

    test('Preview error: retried once without Preview, then never asked again', () async {
      final previewError = fixture('ews_finditem_preview_error.xml');
      final (client, fake) =
          make((r) => (200, r.body.contains('item:Preview') ? previewError : routeOk(r)));

      final inbox = await client.inbox();
      expect(inbox.map((h) => h.id), ids);
      expect(fake.sent, hasLength(2));
      expect(fake.sent[0].body, contains('<t:FieldURI FieldURI="item:Preview"/>'));
      expect(fake.sent[1].body, isNot(contains('item:Preview')));
      expect(fake.sent[1].body, contains('<t:FieldURI FieldURI="message:IsRead"/>'));

      await client.inbox(offset: 30);
      expect(fake.sent, hasLength(3));
      expect(fake.sent[2].body, isNot(contains('item:Preview')));
      expect(fake.sent[2].body, contains('Offset="30"'));
    });

    test('schema validation fault (HTTP 500) is retried the same way', () async {
      final (client, fake) =
          make((r) => r.body.contains('item:Preview') ? (500, schemaFault) : (200, routeOk(r)));
      expect(await client.inbox(), hasLength(5));
      expect(fake.sent, hasLength(2));
    });

    test('a retry that fails too surfaces the error, without looping', () async {
      final (client, fake) = make((r) => (500, schemaFault));
      await expectLater(client.inbox(),
          throwsA(isA<EwsError>().having((e) => e.code, 'code', 'ErrorSchemaValidation')));
      expect(fake.sent, hasLength(2));
    });

    test('a remembered login that starts failing is LoginRequired after one request', () async {
      var accept = true;
      final (client, fake) = make((r) => accept ? (200, routeOk(r)) : (401, ''));
      await client.unreadCount();
      accept = false;
      await expectLater(client.unreadCount(), throwsA(isA<LoginRequired>()));
      expect(fake.sent, hasLength(2));
    });

    test('EWS errors are ParseError with the code only, never the password', () async {
      final (client, fake) = make((r) => (200, itemNotFound));
      final error = await client.body(ids[0]).then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<ParseError>());
      expect((error as EwsError).code, 'ErrorItemNotFound');
      expect(error.toString(), 'Could not read mail (ErrorItemNotFound)');
      expect(fake.sent, hasLength(1));
    });

    test('other HTTP statuses are ParseError', () async {
      final (client, _) = make((r) => (503, '<html><body>Service Unavailable</body></html>'));
      await expectLater(client.unreadCount(),
          throwsA(isA<ParseError>().having((e) => e.what, 'what', 'mail (HTTP 503)')));
    });

    test('network errors are rethrown without the Authorization header', () async {
      final (client, _) = make((r) => throw DioException.connectionError(
          requestOptions: r.options, reason: 'Failed host lookup: mail.inha.uz'));
      final error = await client.inbox().then<Object?>((_) => null, onError: (Object e) => e);
      expect(error, isA<DioException>());
      final e = error as DioException;
      expect(e.requestOptions.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      final secret = base64Encode(utf8.encode('$login:$password'));
      expect(e.toString(), isNot(contains(secret)));
      expect(e.toString(), isNot(contains(password)));
    });
  });
}

typedef Reply = (int status, String body);

/// One request the client sent, as the fake server saw it.
class Sent {
  Sent(this.options, this.body);
  final RequestOptions options;
  final String body;

  /// The username in the Basic Authorization header.
  String get login {
    final header = options.headers['Authorization'] as String;
    final decoded = utf8.decode(base64Decode(header.substring('Basic '.length)));
    return decoded.substring(0, decoded.indexOf(':'));
  }
}

/// A Dio adapter standing in for mail.inha.uz.
class FakeEws implements HttpClientAdapter {
  FakeEws(this.handler);
  final Reply Function(Sent) handler;
  final sent = <Sent>[];

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    final request = Sent(options, utf8.decode(bytes));
    sent.add(request);
    final (status, body) = handler(request);
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [status == 200 || status == 500 ? 'text/xml; charset=utf-8' : 'text/html'],
      if (status == 401) 'www-authenticate': ['Negotiate', 'NTLM', 'Basic realm="mail.inha.uz"'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class FakeCredentials implements CredentialStore {
  FakeCredentials(this.saved);
  Credentials? saved;

  @override
  Future<Credentials?> read(Service s) async => s == Service.mail ? saved : null;

  @override
  Future<void> write(Service s, Credentials c) async => saved = c;

  @override
  Future<void> clear(Service s) async => saved = null;
}
