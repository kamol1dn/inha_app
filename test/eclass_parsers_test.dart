import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/eclass/eclass_parsers.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

DateTime unix(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

void main() {
  group('Course.fromTitle', () {
    test('drops the term-code-section bracket', () {
      final c = Course.fromTitle(1, 'Multimedia Computing[202602-SOC4020-001]');
      expect((c.name, c.code), ('Multimedia Computing', 'SOC4020'));
    });

    test('drops a badge after the bracket, so the name is never a code', () {
      final c = Course.fromTitle(2622, 'Artificial Intelligence[202602-SOC4040-001]NEW');
      expect((c.name, c.code), ('Artificial Intelligence', 'SOC4040'));
      expect(Course.fromTitle(1, 'Artificial Intelligence [202602-SOC4040-001] NEW').name, 'Artificial Intelligence');
    });

    test('keeps a title without the bracket', () {
      expect(Course.fromTitle(1, 'Mental Education').name, 'Mental Education');
    });
  });

  group('parseCourses', () {
    final courses = parseCourses(fixture('eclass_dashboard.html'));

    test('finds every dashboard course once', () {
      expect(courses, hasLength(6));
      expect(courses.map((c) => c.id), [2592, 2615, 2622, 2626, 2634, 2635]);
    });

    test('splits the title into a clean name and code', () {
      final mm = courses.singleWhere((c) => c.id == 2622);
      expect(mm.name, 'Multimedia Computing');
      expect(mm.code, 'SOC4020');
      expect(mm.professor, 'Minhaz Uddin Ahmed');

      final esd = courses.singleWhere((c) => c.id == 2615);
      expect(esd.name, 'Embedded Software & Design');
      expect(esd.code, 'SOC3050');

      for (final c in courses) {
        expect(c.name, isNot(contains('[')));
        expect(c.code, matches(RegExp(r'^[A-Z]+\d+$')));
        expect(c.professor, isNotEmpty);
      }
    });

    test('a dashboard with no courses is empty, not an error', () {
      const html = '<body id="page-site-index"><div class="course_lists">'
          '<ul class="my-course-lists"><li class="nocourses">No courses</li></ul></div></body>';
      expect(parseCourses(html), isEmpty);
    });

    test('an unrecognisable page throws ParseError', () {
      expect(() => parseCourses('<html><body><p>Maintenance</p></body></html>'),
          throwsA(isA<ParseError>()));
      expect(() => parseCourses(fixture('eclass_login.html')), throwsA(isA<ParseError>()));
    });
  });

  group('parseUpcoming', () {
    final events = parseUpcoming(fixture('eclass_upcoming.html'));

    test('finds every event, course-level ones included', () {
      expect(events, hasLength(10));
      final kinds = events.map((e) => e.kind).toList();
      expect(kinds.where((k) => k == DeadlineKind.vod), hasLength(2));
      expect(kinds.where((k) => k == DeadlineKind.assignment), hasLength(1));
      expect(kinds.where((k) => k == DeadlineKind.quiz), hasLength(1));
      // The six course-level "...[001]-N교시" events are class periods, not deadlines.
      expect(kinds.where((k) => k == DeadlineKind.classPeriod), hasLength(6));
      expect(kinds.where((k) => k == DeadlineKind.other), isEmpty);
    });

    test('a VOD window has start and end from the time= stamps', () {
      final vod = events.first;
      expect(vod.title, 'Midterm info');
      expect(vod.kind, DeadlineKind.vod);
      expect(vod.moduleId, 72743);
      expect(vod.moduleType, 'vod');
      expect(vod.courseName, 'Distinguished Lecture in Social Science and Art');
      expect(vod.start, unix(1792177200));
      expect(vod.end, unix(1792954799));
      // 17 Oct 00:00 .. 25 Oct 23:59:59 in Tashkent (UTC+5).
      expect(vod.start!.toUtc(), DateTime.utc(2026, 10, 16, 19));
      expect(vod.end.toUtc(), DateTime.utc(2026, 10, 25, 18, 59, 59));
    });

    test('an assignment has only a due time', () {
      final a = events.singleWhere((e) => e.kind == DeadlineKind.assignment);
      expect(a.title, 'Assignment 1');
      expect(a.courseName, 'Multimedia Computing');
      expect(a.moduleId, 72061);
      expect(a.moduleType, 'assign');
      expect(a.start, isNull);
      expect(a.end.toUtc(), DateTime.utc(2026, 10, 25, 18, 55));
    });

    test('a quiz is recognised from its module link', () {
      final q = events.singleWhere((e) => e.kind == DeadlineKind.quiz);
      expect(q.moduleId, 72454);
      expect(q.moduleType, 'quiz');
      expect(q.courseName, 'Blockchain Basics and Platforms');
      expect(q.end, unix(1792954740));
    });

    test('a course event without a module link is kept, dated by time= not "Today"', () {
      final today = events[2];
      expect(today.title, 'Deep learning for computer vision[001]-9교시');
      expect(today.kind, DeadlineKind.classPeriod);
      expect(today.moduleId, isNull);
      expect(today.moduleType, isNull);
      expect(today.start, isNull);
      expect(today.courseName, 'Deep learning for computer vision');
      expect(today.end, unix(1792609200));
      final tomorrow = events[3];
      expect(tomorrow.title, 'Embedded Software & Design[001]-3교시');
      expect(tomorrow.end, unix(1792695600));
    });

    test('a calendar with no upcoming events is empty, not an error', () {
      const html = '<body id="page-calendar-view"><div class="maincalendar">'
          '<h2>Calendar</h2>There are no upcoming events</div></body>';
      expect(parseUpcoming(html), isEmpty);
    });

    test('an unrecognisable page throws ParseError', () {
      expect(() => parseUpcoming(fixture('eclass_login.html')), throwsA(isA<ParseError>()));
      const noTime = '<div class="eventlist"><div class="event"><h3 class="referer">'
          '<a href="/mod/assign/view.php?id=1">A</a></h3><span class="date">Soon</span></div></div>';
      expect(() => parseUpcoming(noTime), throwsA(isA<ParseError>()));
    });
  });

  group('parseAttendance', () {
    final rows = parseAttendance(fixture('eclass_attendance_2622.html'));

    int count(AttendanceMark m) => rows.where((r) => r.mark == m).length;

    test('reads every class with the column that holds the mark', () {
      expect(rows, hasLength(13));
      expect(count(AttendanceMark.present), 11);
      expect(count(AttendanceMark.absent), 2);
      expect(count(AttendanceMark.late), 0);
      expect(count(AttendanceMark.other), 0);
      expect(count(AttendanceMark.unmarked), 0);
    });

    test('rows carry the date and class label', () {
      expect(rows.first.date, DateTime(2026, 9, 8));
      expect(rows.first.label, '1Class');
      expect(rows.first.mark, AttendanceMark.present);

      final eleventh = rows[10];
      expect(eleventh.date, DateTime(2026, 10, 13));
      expect(eleventh.label, '11Class');
      expect(eleventh.mark, AttendanceMark.absent);

      // The ○ can sit inside a button (auto-attendance) or be plain text.
      expect(rows[11].mark, AttendanceMark.absent);
      expect(rows[9].mark, AttendanceMark.present);
      expect(rows.last.date, DateTime(2026, 10, 21));
    });

    test('a page without the table is empty, an unknown page is a ParseError', () {
      const noTable = '<body id="page-local-ubattendance-my_status">'
          '<div class="attendance"><div class="attendance_book">No attendance</div></div></body>';
      expect(parseAttendance(noTable), isEmpty);
      expect(() => parseAttendance(fixture('eclass_dashboard.html')),
          throwsA(isA<ParseError>()));
    });
  });

  group('parseVodProgress', () {
    final vods = parseVodProgress(fixture('eclass_progress_2592.html'));

    test('reads one row per VOD and skips empty weeks', () {
      expect(vods, hasLength(12));
      expect(vods.map((v) => v.week), [1, 1, 2, 3, 3, 4, 5, 6, 6, 6, 7, 7]);
    });

    test('rows under a rowspan Week cell get that week', () {
      final l62 = vods.singleWhere((v) => v.title == 'Lecture 6-2');
      expect(l62.week, 6); // third row of a rowspan="3" week
      expect(l62.length, const Duration(minutes: 26, seconds: 43));
      expect(l62.percent, 100);
      expect(l62.done, isTrue);

      final midterm = vods.singleWhere((v) => v.title == 'Midterm info');
      expect(midterm.week, 7);
      expect(midterm.length, const Duration(minutes: 3, seconds: 19));

      final video7 = vods.singleWhere((v) => v.title == 'Video 7');
      expect(video7.week, 7);
      expect(video7.length, const Duration(minutes: 55, seconds: 33));
      expect(video7.percent, closeTo(62.86, 1e-9));
      expect(video7.done, isFalse);
    });

    test('parses h:mm:ss lengths and fractional percents', () {
      final l1 = vods.singleWhere((v) => v.title == 'Lecture 1');
      expect(l1.week, 1);
      expect(l1.percent, closeTo(98.21, 1e-9));
      final l2 = vods.singleWhere((v) => v.title == 'Lecture 2');
      expect(l2.length, const Duration(hours: 1, seconds: 34));
    });

    test('a course without progress-managed VODs is empty', () {
      expect(parseVodProgress(fixture('eclass_progress_2635.html')), isEmpty);
    });

    test('an unrecognisable page throws ParseError', () {
      expect(() => parseVodProgress(fixture('eclass_login.html')), throwsA(isA<ParseError>()));
    });
  });

  group('isLoginPage', () {
    test('detects the logged-out login page', () {
      expect(isLoginPage(fixture('eclass_login.html')), isTrue);
    });

    test('logged-in pages are not the login page', () {
      for (final f in [
        'eclass_dashboard.html',
        'eclass_upcoming.html',
        'eclass_attendance_2622.html',
        'eclass_progress_2592.html',
        'eclass_progress_2635.html',
      ]) {
        expect(isLoginPage(fixture(f)), isFalse, reason: f);
      }
    });
  });

  group('extractSesskey', () {
    test('reads M.cfg.sesskey', () {
      expect(extractSesskey(fixture('eclass_dashboard.html')), 'TESTSESSKY');
    });

    test('is null when the page has none', () {
      expect(extractSesskey('<html><body></body></html>'), isNull);
    });
  });
}
