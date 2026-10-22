import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';

import 'fakes.dart';

void main() {
  final offline = DioException.connectionError(
      requestOptions: RequestOptions(path: 'https://eclass.inha.ac.kr/'), reason: 'Failed host lookup');

  group('Save and test', () {
    test('a working login is recorded as signed in, then the data refreshes', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.deadlines = [
        Deadline(title: 'Lab 5', courseName: 'Multimedia Computing', kind: DeadlineKind.assignment, end: DateTime(2026, 10, 25))
      ];
      expect(await data.testLogin(Service.eclass), isNull);
      expect(eclass.logins, 1);
      expect(data.prefs.accountCheck(Service.eclass)!.ok, isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(data.deadlines.data?.value.single.title, 'Lab 5');
    });

    test('a rejected login is recorded and returned', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.loginError = LoginRequired(Service.eclass, 'eClass rejected the saved login');
      expect(await data.testLogin(Service.eclass), isA<LoginRequired>());
      expect(data.prefs.accountCheck(Service.eclass)!.ok, isFalse);
    });

    test('a network failure says nothing about the login', () async {
      final (data, _, _, ins, _) = await makeAppData();
      ins.loginError = offline;
      expect(await data.testLogin(Service.ins), isA<DioException>());
      expect(data.prefs.accountCheck(Service.ins), isNull);
    });

    test('mail is checked with the unread count', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.error = LoginRequired(Service.mail);
      expect(await data.testLogin(Service.mail), isA<LoginRequired>());
      expect(data.prefs.accountCheck(Service.mail)!.ok, isFalse);
      mail.error = null;
      expect(await data.testLogin(Service.mail), isNull);
      expect(data.prefs.accountCheck(Service.mail)!.ok, isTrue);
    });
  });

  test('every refresh updates the account status as it goes', () async {
    final (data, _, _, _, mail) = await makeAppData();
    await data.refreshMail();
    final first = data.prefs.accountCheck(Service.mail)!;
    expect(first.ok, isTrue);

    mail.error = offline;
    await data.refreshMail();
    expect(data.prefs.accountCheck(Service.mail)!.at, first.at); // unchanged

    mail.error = LoginRequired(Service.mail);
    await data.refreshMail();
    expect(data.prefs.accountCheck(Service.mail)!.ok, isFalse);

    await data.refreshTimetable(); // EduPage has no login
    expect(data.prefs.accountCheck(Service.edupage), isNull);
  });

  test('signing out forgets the service: its cache, its status, nothing else', () async {
    final (data, _, timetable, _, mail) = await makeAppData();
    mail.all = [mailHeader(0, unread: true)];
    mail.unread = 1;
    timetable.lessonList = const [Lesson(weekday: 1, start: '09:00', end: '10:30', subject: 'Artificial Intelligence')];
    await data.refreshMail();
    await data.refreshTimetable();

    await data.forget(Service.mail);
    expect(data.inbox.data, isNull);
    expect(data.mailUnread.data, isNull);
    expect(data.prefs.accountCheck(Service.mail), isNull);
    await data.reloadFromCache(); // not just in memory
    expect(data.inbox.data, isNull);
    expect(data.lessons.data?.value, hasLength(1));
  });

  test('AccountCheck survives a bad stored value', () async {
    final (data, _, _, _, _) = await makeAppData(prefs: {'account.eclass': 'not json'});
    expect(data.prefs.accountCheck(Service.eclass), isNull);
  });
}
