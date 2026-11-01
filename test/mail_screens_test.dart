import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/app.dart';
import 'package:inha_app/core/cache.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/features/compose_screen.dart';
import 'package:inha_app/features/mail_screen.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/mail/ews_soap.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// Search, attachments in and out, leaving the composer, and the states around
// them. Names and addresses are made up.

/// [FakeMail] with whole messages, and calls that wait until they are let go.
class GatedMail extends FakeMail {
  final messages = <String, MailMessage>{};
  Completer<void>? moveGate;
  Completer<void>? sendGate;
  Completer<void>? fileGate;
  final fetched = <String>[];

  @override
  Future<MailMessage> message(String id) async {
    if (error != null) throw error!;
    return messages[id] ?? super.message(id);
  }

  @override
  Future<String?> move(String id, MailFolder to) async {
    await moveGate?.future;
    return super.move(id, to);
  }

  @override
  Future<void> send(OutgoingMail m) async {
    await sendGate?.future;
    return super.send(m);
  }

  @override
  Future<MailFile> attachment(String id) async {
    fetched.add(id);
    await fileGate?.future;
    return super.attachment(id);
  }
}

Future<(AppData, GatedMail)> makeData() async {
  SharedPreferences.setMockInitialValues({'prefs.defaultsSettled': true, 'classGroup': 'ICE23-1'});
  final p = await SharedPreferences.getInstance();
  final mail = GatedMail();
  final data = AppData(
      eclass: FakeEclass(), timetable: FakeTimetable(), ins: FakeIns(), mail: mail, cache: JsonCache(p), prefs: Prefs(p));
  return (data, mail);
}

/// Puts [screen] on a route above a plain home, as the app pushes it.
Future<void> push(WidgetTester tester, AppData data, Widget screen, {double scale = 1}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: data,
    child: MaterialApp(
      theme: InhaApp.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: screen))),
                child: const Text('Home'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Home'));
  await tester.pumpAndSettle();
}

/// The phone's Back button.
Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

MailMessage message({String id = 'id0', List<MailAttachment> attachments = const [], String body = 'Rooms are on eClass.'}) =>
    MailMessage(
      id: id,
      from: 'Academic Affairs',
      fromAddress: 'affairs@inha.example',
      subject: 'Midterm rooms',
      received: DateTime(2026, 10, 20, 9),
      body: body,
      attachments: attachments,
    );

MailHeader header({String id = 'id0', bool unread = false, bool files = false}) => MailHeader(
    id: id,
    from: 'Academic Affairs',
    subject: 'Midterm rooms',
    received: DateTime(2026, 10, 20, 9),
    unread: unread,
    hasAttachments: files);

void main() {
  group('saving an attachment', () {
    test('a name from a message stays in its folder and keeps its ending', () {
      expect(safeFileName('Midterm rooms.pdf'), 'Midterm rooms.pdf');
      expect(safeFileName('../../databases/app.db'), 'app.db');
      expect(safeFileName(r'..\..\evil.docx'), 'evil.docx');
      expect(safeFileName('..hidden.txt'), 'hidden.txt');
      expect(safeFileName('a:b*c?.txt'), 'a_b_c_.txt');
      expect(safeFileName('report‮fdp.exe'), 'reportfdp.exe');
      expect(safeFileName(''), 'Attachment');
      expect(safeFileName('..'), 'Attachment');
      expect(safeFileName('/'), 'Attachment');
      final long = safeFileName('${'과' * 200}.pdf');
      expect(long.runes.length, 80);
      expect(long, endsWith('과.pdf'));
    });

    test('only the file last opened stays on the phone', () async {
      final dir = await Directory.systemTemp.createTemp('mail_files');
      addTearDown(() => dir.delete(recursive: true));
      final sub = Directory('${dir.path}/mail_files');
      final first = await saveMailFile(const MailFile(name: 'a.pdf', bytes: [1, 2]), sub);
      expect(await first.readAsBytes(), [1, 2]);
      final second = await saveMailFile(const MailFile(name: '../b.pdf', bytes: [3]), sub);
      expect(second.path, '${sub.path}/b.pdf');
      expect(await second.readAsBytes(), [3]);
      expect(sub.listSync().map((f) => f.path), [second.path]);
    });

    test('a file is opened by its type, or by its name when the type says nothing', () {
      expect(openAsType('application/pdf'), 'application/pdf');
      expect(openAsType('Application/PDF; name="a.pdf"'), 'application/pdf');
      expect(openAsType('application/octet-stream'), isNull);
      expect(openAsType(''), isNull);
    });
  });

  group('composeError', () {
    test('names what happened', () {
      expect(composeError(LoginRequired(Service.mail), sending: true), 'Mail sign-in needed.');
      expect(composeError(EwsError('ErrorInvalidRecipients'), sending: true), "Mail didn't accept one of the addresses.");
      expect(composeError(EwsError('ErrorMessageSizeExceeded'), sending: true),
          'Mail refused the attachment: it is too big.');
      expect(composeError(ParseError('mail (HTTP 413)'), sending: false), 'Mail refused the attachment: it is too big.');
      expect(composeError(Exception('x'), sending: true), "Mail didn't send it. Try again.");
      expect(composeError(Exception('x'), sending: false), "Mail didn't save the draft. Try again.");
    });

    test('with files, what was saved first may be in Drafts', () {
      expect(composeError(Exception('x'), sending: true, withFiles: true),
          "Mail didn't send it. Try again. A copy may be in Drafts.");
      expect(composeError(LoginRequired(Service.mail), sending: true, withFiles: true), 'Mail sign-in needed.');
    });
  });

  group('message', () {
    testWidgets('Back during a move leaves the screen under it alone (F112)', (tester) async {
      final (data, mail) = await makeData();
      mail.messages['id0'] = message();
      mail.moveGate = Completer();
      await push(tester, data, MailMessageScreen(header: header()));
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await pressBack(tester);
      expect(find.text('Home'), findsOneWidget);

      mail.moveGate!.complete();
      await tester.pumpAndSettle();
      expect(mail.moves.single.$1, 'id0');
      expect(find.text('Home'), findsOneWidget, reason: 'the home route is still there');
      expect(find.text('Moved to Deleted.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('a move closes the message and offers Undo', (tester) async {
      final (data, mail) = await makeData();
      mail.messages['id0'] = message();
      MailHeader? told = header();
      await push(tester, data, MailMessageScreen(header: header(), onChanged: (h) => told = h));
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(MailMessageScreen), findsNothing);
      expect(told, isNull);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(mail.moves.last, ('moved-id0', MailFolder.inbox));
    });

    testWidgets('Reply waits while it is moving', (tester) async {
      final (data, mail) = await makeData();
      mail.messages['id0'] = message();
      mail.moveGate = Completer();
      await push(tester, data, MailMessageScreen(header: header()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pump();
      await tester.tap(find.text('Forward'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsNothing);
      mail.moveGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('an expired login offers Sign in, not Retry (F142)', (tester) async {
      final (data, mail) = await makeData();
      mail.error = LoginRequired(Service.mail);
      await push(tester, data, MailMessageScreen(header: header()));
      await tester.pumpAndSettle();
      expect(find.text('Mail sign-in needed.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
    });

    testWidgets('another failure offers Retry, which loads it', (tester) async {
      final (data, mail) = await makeData();
      mail.error = Exception('down');
      mail.messages['id0'] = message();
      await push(tester, data, MailMessageScreen(header: header()));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Sign in'), findsNothing);
      mail.error = null;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Rooms are on eClass.', findRichText: true), findsOneWidget);
    });

    group('attachments (F113)', () {
      const pdf = MailAttachment(id: 'a1', name: 'Rooms.pdf', size: 48213, contentType: 'application/pdf');

      testWidgets('a tap fetches the file, with a spinner, and opens it', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['id0'] = message(attachments: const [pdf]);
        mail.files = {'a1': const MailFile(name: 'Rooms.pdf', contentType: 'application/pdf', bytes: [1, 2, 3])};
        mail.fileGate = Completer();
        final opened = <MailFile>[];
        await push(tester, data, MailMessageScreen(header: header(), openFile: (f) async {
          opened.add(f);
          return null;
        }));
        await tester.pumpAndSettle();
        expect(find.text('47 KB'), findsOneWidget);
        expect(tester.getSize(find.byType(AttachmentRow)).height, greaterThanOrEqualTo(48));

        await tester.tap(find.text('Rooms.pdf'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.text('Rooms.pdf')); // a second tap asks for nothing more
        await tester.pump();
        expect(mail.fetched, ['a1']);

        mail.fileGate!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(opened.single.bytes, [1, 2, 3]);
        expect(opened.single.contentType, 'application/pdf');
        expect(find.byType(SnackBar), findsNothing);
      });

      testWidgets('what stopped it goes in a snack bar', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['id0'] = message(attachments: const [pdf]);
        mail.files = {'a1': const MailFile(name: 'Rooms.pdf', bytes: [1])};
        await push(tester, data,
            MailMessageScreen(header: header(), openFile: (f) async => 'No app on this phone opens ${f.name}.'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rooms.pdf'));
        await tester.pumpAndSettle();
        expect(find.text('No app on this phone opens Rooms.pdf.'), findsOneWidget);
      });

      Future<void> failing(WidgetTester tester, Object error, String says, {bool signIn = false}) async {
        final (data, mail) = await makeData();
        mail.messages['id0'] = message(attachments: const [pdf]);
        await push(tester, data, MailMessageScreen(header: header(), openFile: (_) async => null));
        await tester.pumpAndSettle();
        mail.error = error;
        await tester.tap(find.text('Rooms.pdf'));
        await tester.pumpAndSettle();
        expect(find.text(says), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Sign in'), signIn ? findsOneWidget : findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }

      testWidgets('an attached message can only be read in webmail', (tester) async {
        await failing(tester, ParseError('mail (GetAttachment)'),
            "Couldn't open Rooms.pdf here. An attached message opens only in webmail.");
      });

      testWidgets('an expired login offers Sign in', (tester) async {
        await failing(tester, LoginRequired(Service.mail), 'Mail sign-in needed.', signIn: true);
      });

      testWidgets("Exchange's own refusal names the file", (tester) async {
        await failing(tester, EwsError('ErrorInvalidIdMalformed'), "Couldn't get Rooms.pdf from Mail.");
      });

      testWidgets('Back while it is fetching opens nothing', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['id0'] = message(attachments: const [pdf]);
        mail.files = {'a1': const MailFile(name: 'Rooms.pdf', bytes: [1])};
        mail.fileGate = Completer();
        var opened = false;
        await push(tester, data, MailMessageScreen(header: header(), openFile: (_) async {
          opened = true;
          return null;
        }));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rooms.pdf'));
        await tester.pump();
        await pressBack(tester);
        mail.fileGate!.complete();
        await tester.pumpAndSettle();
        expect(opened, isFalse);
      });

      testWidgets('one with no id is listed and does nothing', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['id0'] = message(attachments: const [MailAttachment(name: 'Forwarded message', size: 900)]);
        await push(tester, data, MailMessageScreen(header: header(), openFile: (_) async => null));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Forwarded message'));
        await tester.pumpAndSettle();
        expect(mail.fetched, isEmpty);
      });
    });
  });

  group('list rows', () {
    Future<void> showList(WidgetTester tester, AppData data, {MailFolder folder = MailFolder.inbox}) async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: data,
        child: MaterialApp(theme: InhaApp.light, home: Scaffold(body: MailScreen(folder: folder))),
      ));
      await tester.pump();
    }

    testWidgets('a screen reader hears unread and attachments (F143, F113)', (tester) async {
      final handle = tester.ensureSemantics();
      final (data, mail) = await makeData();
      mail.all = [header(id: 'id0', unread: true, files: true), header(id: 'id1')];
      await data.refreshMail();
      await showList(tester, data);
      expect(find.bySemanticsLabel(RegExp('Unread: Midterm rooms')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Has attachments')), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(tester.getSize(find.byIcon(Icons.attach_file)), const Size(16, 16));
      handle.dispose();
    });

    testWidgets('the drawer says which folder is selected and what the count means (F143)', (tester) async {
      final handle = tester.ensureSemantics();
      final (data, mail) = await makeData();
      mail.unread = 5;
      mail.counts = {MailFolder.drafts: const MailFolderCount(0, 2)};
      await data.refreshMail();
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: data,
        child: MaterialApp(
          theme: InhaApp.light,
          home: Scaffold(body: MailDrawer(selected: MailFolder.inbox, onSelect: (_) {})),
        ),
      ));
      await tester.pump();

      SemanticsData of(String folder) => tester.getSemantics(find.text(folder)).getSemanticsData();
      expect(of('Inbox').flagsCollection.isSelected, Tristate.isTrue);
      expect(of('Sent').flagsCollection.isSelected, Tristate.isFalse);
      expect(of('Inbox').label, contains('5 unread'));
      expect(of('Drafts').label, contains('2 waiting'));
      handle.dispose();
    });
  });

  group('search', () {
    Future<void> ask(WidgetTester tester, String q) async {
      await tester.enterText(find.byType(TextField), q);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    testWidgets('asks when told to, in the folder on show, and lists what it finds', (tester) async {
      final (data, mail) = await makeData();
      mail.folders[MailFolder.sent] = [
        const MailHeader(id: 's1', from: '', to: 'Prof. Kim', subject: 'Lab report', received: _when),
        const MailHeader(id: 's2', from: '', to: 'Dean', subject: 'Leave of absence', received: _when),
      ];
      await push(tester, data, const MailSearchScreen(folder: MailFolder.sent));
      expect(find.text('Search Sent'), findsOneWidget);
      expect(find.text('Finds mail in Sent by subject, text or person.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Lab');
      await tester.pump();
      expect(mail.searches, isEmpty, reason: 'not on every letter');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(mail.searches, [(MailFolder.sent, 'Lab')]);
      expect(find.text('Lab report'), findsOneWidget);
      expect(find.text('To Prof. Kim'), findsOneWidget);
      expect(find.text('Leave of absence'), findsNothing);
    });

    testWidgets('nothing found says so, and blank asks nothing', (tester) async {
      final (data, mail) = await makeData();
      await push(tester, data, const MailSearchScreen(folder: MailFolder.inbox));
      await ask(tester, '   ');
      expect(mail.searches, isEmpty);
      await ask(tester, ' lab report ');
      expect(mail.searches, [(MailFolder.inbox, 'lab report')]);
      expect(find.text('No mail matches "lab report" in Inbox.'), findsOneWidget);
    });

    testWidgets('Clear starts over and drops an answer on its way', (tester) async {
      final (data, mail) = await makeData();
      mail.all = [header()];
      await push(tester, data, const MailSearchScreen(folder: MailFolder.inbox));
      await ask(tester, 'Midterm');
      expect(find.text('Midterm rooms'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Midterm rooms'), findsNothing);
      expect(find.text('Finds mail in Inbox by subject, text or person.'), findsOneWidget);
    });

    testWidgets('a failure names Mail; Retry asks again; a login offers Sign in', (tester) async {
      final (data, mail) = await makeData();
      mail.all = [header()];
      mail.error = Exception('down');
      await push(tester, data, const MailSearchScreen(folder: MailFolder.inbox));
      await ask(tester, 'Midterm');
      expect(find.text("Couldn't load from Mail."), findsOneWidget);
      mail.error = null;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Midterm rooms'), findsOneWidget);

      mail.error = LoginRequired(Service.mail);
      await ask(tester, 'Midterm');
      expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('the next page comes as the end comes into view, and a failed one can be retried', (tester) async {
      final (data, mail) = await makeData();
      mail.all = [
        for (var i = 0; i < 45; i++)
          MailHeader(id: 'id$i', from: 'Academic Affairs', subject: 'Midterm $i', received: _when),
      ];
      await push(tester, data, const MailSearchScreen(folder: MailFolder.inbox));
      await ask(tester, 'Midterm');
      expect(mail.searches, hasLength(1));

      mail.error = Exception('down');
      await tester.drag(find.byType(ListView), const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(mail.searches, hasLength(2));
      await tester.scrollUntilVisible(find.widgetWithText(TextButton, 'Retry'), 300,
          scrollable: find.byType(Scrollable).last);
      mail.error = null;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Midterm 44'), 600, scrollable: find.byType(Scrollable).last);
      expect(find.text('Midterm 44'), findsOneWidget);
    });

    testWidgets('a result read or moved changes its row', (tester) async {
      final (data, mail) = await makeData();
      mail.all = [header(unread: true)];
      mail.messages['id0'] = MailMessage(
          id: 'id0', from: 'Academic Affairs', subject: 'Midterm rooms', received: _when, body: 'x', unread: true);
      final handle = tester.ensureSemantics();
      await push(tester, data, const MailSearchScreen(folder: MailFolder.inbox));
      await ask(tester, 'Midterm');
      expect(find.bySemanticsLabel(RegExp('Unread: Midterm')), findsOneWidget);

      await tester.tap(find.text('Midterm rooms'));
      await tester.pumpAndSettle();
      expect(mail.marked.single, ('id0', true));
      await pressBack(tester);
      expect(find.bySemanticsLabel(RegExp('Unread: Midterm')), findsNothing);

      await tester.tap(find.text('Midterm rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(MailMessageScreen), findsNothing);
      expect(find.byType(MailSearchScreen), findsOneWidget);
      expect(find.text('Midterm rooms'), findsNothing);
      handle.dispose();
    });

    testWidgets('a draft found opens in the composer, and the search runs again after', (tester) async {
      final (data, mail) = await makeData();
      mail.folders[MailFolder.drafts] = [header(id: 'd1')];
      mail.messages['d1'] = message(id: 'd1');
      await push(tester, data, const MailSearchScreen(folder: MailFolder.drafts));
      await ask(tester, 'Midterm');
      await tester.tap(find.text('Midterm rooms'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposeScreen), findsOneWidget);
      await pressBack(tester);
      expect(find.byType(MailSearchScreen), findsOneWidget);
      expect(mail.searches, hasLength(2));
    });
  });

  group('composer', () {
    Finder field(String hint) => find.widgetWithText(TextField, hint);
    PickedFile picked(String name, int size, {int? said}) =>
        PickedFile(name, said ?? size, () async => List.filled(size, 0));

    group('leaving (F116, F117)', () {
      testWidgets('nothing written leaves at once', (tester) async {
        final (data, _) = await makeData();
        await push(tester, data, const ComposeScreen());
        await pressBack(tester);
        expect(find.byType(ComposeScreen), findsNothing);
      });

      testWidgets('only a recipient typed still asks', (tester) async {
        final (data, _) = await makeData();
        await push(tester, data, const ComposeScreen());
        await tester.enterText(field('Name or address'), 'a@x.example');
        await pressBack(tester);
        expect(find.text('Keep this as a draft?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(ComposeScreen), findsNothing);
      });

      testWidgets('a recipient picked from the directory still asks', (tester) async {
        final (data, mail) = await makeData();
        mail.directory = const [MailAddress('Dilnoza K.', 'd.k@inha.example')];
        await push(tester, data, const ComposeScreen());
        await tester.enterText(field('Name or address'), 'Dil');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dilnoza K.'));
        await tester.pumpAndSettle();
        await pressBack(tester);
        expect(find.text('Keep this as a draft?'), findsOneWidget);
      });

      testWidgets('a changed recipient on a draft asks; an untouched draft does not', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['d1'] = MailMessage(
            id: 'd1', from: '', subject: 'S', received: _when, body: '', to: const [MailAddress('', 'a@x.example')]);
        await push(tester, data, ComposeScreen(kind: ComposeKind.draft, draft: header(id: 'd1')));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'a@x.example'), 'b@x.example');
        await pressBack(tester);
        expect(find.text('Save your changes?'), findsOneWidget);
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        expect(mail.saved.single.to, ['b@x.example']);
        expect(mail.saved.single.body, isNull);
      });

      testWidgets('Back waits for a send, and a failure keeps the writing', (tester) async {
        final (data, mail) = await makeData();
        mail.sendGate = Completer();
        await push(tester, data, const ComposeScreen());
        await tester.enterText(field('Name or address'), 'a@x.example');
        await tester.enterText(field('Write your message'), 'A long message');
        await tester.tap(find.byTooltip('Send'));
        await tester.pump();

        await pressBackDuringWork(tester);
        expect(find.byType(ComposeScreen), findsOneWidget);
        expect(find.text('Keep this as a draft?'), findsNothing);

        mail.error = Exception('down');
        mail.sendGate!.complete();
        await tester.pumpAndSettle();
        expect(find.text("Mail didn't send it. Try again."), findsOneWidget);
        expect(find.text('A long message'), findsOneWidget);
      });

      testWidgets('a send that works closes it and says so', (tester) async {
        final (data, mail) = await makeData();
        await push(tester, data, const ComposeScreen());
        await tester.enterText(field('Name or address'), 'a@x.example');
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        expect(mail.sent.single.to, ['a@x.example']);
        expect(find.byType(ComposeScreen), findsNothing);
        expect(find.text('Sent.'), findsOneWidget);
      });
    });

    group('attaching (F166)', () {
      testWidgets('a picked file shows, goes with the message, and asks before leaving', (tester) async {
        final (data, mail) = await makeData();
        await push(tester, data, ComposeScreen(pickFiles: () async => [picked('Medical note.pdf', 48213)]));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        expect(find.text('Medical note.pdf'), findsOneWidget);
        expect(find.text('47 KB'), findsOneWidget);

        await pressBack(tester);
        expect(find.text('Keep this as a draft?'), findsOneWidget);
        await tester.tap(find.text('Save draft'));
        await tester.pumpAndSettle();
        expect(mail.saved.single.attachments.single.name, 'Medical note.pdf');
        expect(mail.saved.single.attachments.single.bytes, hasLength(48213));
      });

      testWidgets('a file can be taken off again', (tester) async {
        final (data, mail) = await makeData();
        await push(tester, data, ComposeScreen(pickFiles: () async => [picked('a.pdf', 10), picked('b.pdf', 20)]));
        await tester.enterText(field('Name or address'), 'x@x.example');
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Remove a.pdf'));
        await tester.pumpAndSettle();
        expect(find.text('a.pdf'), findsNothing);
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        expect(mail.sent.single.attachments.map((f) => f.name), ['b.pdf']);
      });

      testWidgets('backing out of the picker changes nothing', (tester) async {
        final (data, _) = await makeData();
        await push(tester, data, ComposeScreen(pickFiles: () async => const []));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        await pressBack(tester);
        expect(find.byType(ComposeScreen), findsNothing);
      });

      testWidgets('a file too big is refused before it is read', (tester) async {
        final (data, _) = await makeData();
        var read = false;
        await push(
            tester,
            data,
            ComposeScreen(
                pickFiles: () async => [
                      PickedFile('Lecture.mp4', maxMailAttachmentBytes + 1, () async {
                        read = true;
                        return const [];
                      })
                    ]));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        expect(read, isFalse);
        expect(find.text('Lecture.mp4 is too big to add. A message can carry 25 MB of new files.'), findsOneWidget);
        expect(find.byType(AttachmentRow), findsNothing);
      });

      testWidgets('the limit is for all the new files together, and an unknown size is checked once read', (tester) async {
        final (data, _) = await makeData();
        const fifteen = 15 * 1024 * 1024;
        await push(tester, data,
            ComposeScreen(pickFiles: () async => [picked('one.pdf', fifteen), PickedFile('two.pdf', null, () async => List.filled(fifteen, 0))]));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        expect(find.text('one.pdf'), findsOneWidget);
        expect(find.text('two.pdf is too big to add. A message can carry 25 MB of new files.'), findsOneWidget);
        expect(find.byType(AttachmentRow), findsOneWidget);
      });

      testWidgets("a file that can't be read, or no picker, says so", (tester) async {
        final (data, _) = await makeData();
        await push(
            tester,
            data,
            ComposeScreen(
                pickFiles: () async => [PickedFile('gone.pdf', 10, () async => throw const FileSystemException())]));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        expect(find.text("Couldn't read gone.pdf."), findsOneWidget);
        expect(find.byTooltip('Attach file'), findsOneWidget);
      });

      testWidgets('a reply and a forward carry files too', (tester) async {
        final (data, mail) = await makeData();
        final ref = message();
        await push(tester, data,
            ComposeScreen(kind: ComposeKind.reply, ref: ref, pickFiles: () async => [picked('a.pdf', 10)]));
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        expect(mail.sent.single.kind, ComposeKind.reply);
        expect(mail.sent.single.attachments.single.name, 'a.pdf');
      });

      testWidgets('a failed send with files says a copy may be in Drafts', (tester) async {
        final (data, mail) = await makeData();
        await push(tester, data, ComposeScreen(pickFiles: () async => [picked('a.pdf', 10)]));
        await tester.enterText(field('Name or address'), 'x@x.example');
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        mail.error = Exception('down');
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        expect(find.text("Mail didn't send it. Try again. A copy may be in Drafts."), findsOneWidget);
        expect(find.text('a.pdf'), findsOneWidget);
      });

      testWidgets("a draft's saved files are listed and can't be removed here", (tester) async {
        final (data, mail) = await makeData();
        mail.messages['d1'] = MailMessage(
            id: 'd1',
            from: '',
            subject: 'S',
            received: _when,
            body: '',
            attachments: const [MailAttachment(id: 'a1', name: 'Saved.pdf', size: 2048)]);
        await push(tester, data, ComposeScreen(kind: ComposeKind.draft, draft: header(id: 'd1')));
        await tester.pumpAndSettle();
        expect(find.text('Saved.pdf'), findsOneWidget);
        expect(find.byTooltip('Remove Saved.pdf'), findsNothing);
        await pressBack(tester);
        expect(find.byType(ComposeScreen), findsNothing, reason: 'nothing changed');
      });
    });

    group('deleting a draft (F182)', () {
      testWidgets('says so with Undo, which puts it back', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['d1'] = message(id: 'd1');
        await push(tester, data, ComposeScreen(kind: ComposeKind.draft, draft: header(id: 'd1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete draft'));
        await tester.pumpAndSettle();
        expect(mail.moves.single, ('d1', MailFolder.deleted));
        expect(find.text('Draft moved to Deleted.'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(mail.moves.last, ('moved-d1', MailFolder.drafts));
      });

      testWidgets('an Undo that fails says so', (tester) async {
        final (data, mail) = await makeData();
        mail.messages['d1'] = message(id: 'd1');
        await push(tester, data, ComposeScreen(kind: ComposeKind.draft, draft: header(id: 'd1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete draft'));
        await tester.pumpAndSettle();
        mail.error = Exception('down');
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(find.text("Couldn't move it back to Drafts."), findsOneWidget);
      });
    });

    group('header lines (F145, F142)', () {
      testWidgets('a tap anywhere on a line lands in its field', (tester) async {
        final (data, _) = await makeData();
        await push(tester, data, const ComposeScreen());
        expect(tester.getSize(find.byType(TextField).first).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(field('Name or address')).height, greaterThanOrEqualTo(48));
        final top = tester.getTopLeft(field('Name or address'));
        await tester.tapAt(top + const Offset(40, 3));
        await tester.pump();
        expect(tester.widget<TextField>(field('Name or address')).controller, isNotNull);
        expect(tester.binding.focusManager.primaryFocus?.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      });

      testWidgets('a screen reader hears the label with the field', (tester) async {
        final handle = tester.ensureSemantics();
        final (data, _) = await makeData();
        await push(tester, data, const ComposeScreen());
        final subject = tester.getSemantics(find.text('Subject')).getSemanticsData();
        expect(subject.label, contains('Subject'));
        expect(subject.flagsCollection.isTextField, isTrue);
        handle.dispose();
      });

      testWidgets('at text scale 2.0 a label stays whole and nothing overflows', (tester) async {
        final (data, mail) = await makeData();
        mail.directory = const [MailAddress('Dilnoza K.', 'd.k@inha.example')];
        await push(tester, data, ComposeScreen(pickFiles: () async => [picked('Medical note with a long name.pdf', 48213)]),
            scale: 2);
        await tester.tap(find.byTooltip('Attach file'));
        await tester.pumpAndSettle();
        final label = tester.renderObject<RenderParagraph>(find.text('Subject'));
        expect(label.didExceedMaxLines, isFalse);
        expect(label.size.height, lessThan(2 * 20 * 1.5), reason: 'one line');
        expect(tester.takeException(), isNull);
      });

      testWidgets('an expired login on a draft offers Sign in, not Retry', (tester) async {
        final (data, mail) = await makeData();
        mail.error = LoginRequired(Service.mail);
        await push(tester, data, ComposeScreen(kind: ComposeKind.draft, draft: header(id: 'd1')));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
        await pressBack(tester);
        expect(find.byType(ComposeScreen), findsNothing);
      });

      testWidgets('an expired login on a send offers Sign in in the snack bar', (tester) async {
        final (data, mail) = await makeData();
        await push(tester, data, const ComposeScreen());
        await tester.enterText(field('Name or address'), 'a@x.example');
        mail.error = LoginRequired(Service.mail);
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        expect(find.text('Mail sign-in needed.'), findsOneWidget);
        expect(find.widgetWithText(SnackBarAction, 'Sign in'), findsOneWidget);
      });
    });
  });
}

/// Back while a progress bar runs: pumpAndSettle would never finish.
Future<void> pressBackDuringWork(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const _when = _Moment();

class _Moment implements DateTime {
  const _Moment();
  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime(2026, 10, 20, 9).noSuchMethod(invocation);
}
