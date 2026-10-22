import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/urgency.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:inha_app/services/eclass/eclass_parsers.dart';

import 'fakes.dart';

/// eClass's assignment page, cut down to what the parser reads. The markup
/// follows the live page (Coursemos keeps Moodle's assign renderer): the
/// status cell has no state class until there is a submission.
String assignPage({String statusCell = '<td class="cell c1 lastcol">No attempt</td>',
        String grading = '<td class="submissionnotgraded cell c1 lastcol">Not graded</td>',
        String modified = '-'}) =>
    '''
<html><body id="page-mod-assign-view"><div id="region-main"><div role="main">
<h2>Lab 5: JPEG quantization</h2>
<div class="submissionstatustable"><h3>Submission status</h3>
<div class="box boxaligncenter submissionsummarytable"><table class="generaltable"><tbody>
<tr><td class="cell c0">Submission status</td>$statusCell</tr>
<tr><td class="cell c0">Grading status</td>$grading</tr>
<tr><td class="cell c0">Due date</td><td class="cell c1 lastcol">2026-10-25 23:55</td></tr>
<tr><td class="cell c0">Time remaining</td><td class="cell c1 lastcol">2 days 22 hours</td></tr>
<tr><td class="cell c0">Last modified</td><td class="cell c1 lastcol">$modified</td></tr>
<tr class="lastrow"><td class="cell c0">Submission comments</td><td class="cell c1 lastcol">Comments (0)</td></tr>
</tbody></table></div></div></div></div></body></html>''';

/// eClass's quiz page: the info box and, once attempted, the attempts table.
String quizPage({List<String> states = const []}) => '''
<html><body id="page-mod-quiz-view"><div id="region-main"><div role="main">
<h2>Quiz 2: Week 6</h2>
<div class="box quizinfo well"><p>Attempts allowed: 1</p><p>This quiz will close at 2026-10-25 23:59</p></div>
${states.isEmpty ? '<div class="box quizattempt"><form><button>Attempt quiz now</button></form></div>' : '''
<table class="generaltable quizattemptsummary"><thead><tr><th class="header c0">State</th>
<th class="header c1">Grade / 100.00</th><th class="header c2 lastcol">Review</th></tr></thead><tbody>
${states.map((s) => '<tr><td class="cell c0">$s</td><td class="cell c1">37.00</td><td class="cell c2 lastcol"><a>Review</a></td></tr>').join()}
</tbody></table><div class="box quizattempt"><p>No more attempts are allowed</p></div>'''}
</div></div></body></html>''';

Deadline item(DeadlineKind kind, int id, {bool done = false, DateTime? doneAt}) => Deadline(
    title: 'Lab $id',
    courseName: 'Multimedia Computing',
    kind: kind,
    end: DateTime(2026, 10, 25, 23, 55),
    moduleId: id,
    moduleType: kind == DeadlineKind.quiz ? 'quiz' : 'assign',
    done: done,
    doneAt: doneAt);

void main() {
  group('assignment page', () {
    test('no attempt is not done', () {
      expect(parseAssignSubmission(assignPage()), (done: false, at: null));
    });

    test('submitted for grading is done, at the last modified time', () {
      final s = parseAssignSubmission(assignPage(
          statusCell: '<td class="submissionstatussubmitted cell c1 lastcol">Submitted for grading</td>',
          modified: '2026-10-21 21:14'));
      expect(s, (done: true, at: DateTime(2026, 10, 21, 21, 14)));
    });

    test('a draft is not handed in', () {
      final s = parseAssignSubmission(assignPage(
          statusCell: '<td class="submissionstatusdraft cell c1 lastcol">Draft (not submitted)</td>',
          modified: '2026-10-21 21:14'));
      expect(s, (done: false, at: null));
    });

    test('graded counts as done whatever the status cell says', () {
      final s = parseAssignSubmission(
          assignPage(grading: '<td class="submissiongraded cell c1 lastcol">Graded</td>'));
      expect(s.done, isTrue);
    });

    test('the same classes in Korean are read the same', () {
      final s = parseAssignSubmission(assignPage(
              statusCell: '<td class="submissionstatussubmitted cell c1 lastcol">채점을 위해 제출됨</td>',
              modified: '2026-10-21 21:14')
          .replaceFirst('Last modified', '최종 수정 일시'));
      expect(s, (done: true, at: DateTime(2026, 10, 21, 21, 14)));
    });

    test('another page is a ParseError', () {
      expect(() => parseAssignSubmission('<html><body id="page-login-index"></body></html>'),
          throwsA(isA<ParseError>()));
    });
  });

  group('quiz page', () {
    test('not attempted is not done', () {
      expect(parseQuizSubmission(quizPage()), (done: false, at: null));
    });

    test('a finished attempt is done, at its submitted time', () {
      expect(parseQuizSubmission(quizPage(states: ['Finished<span class="statedetails">Submitted 2026-10-04 23:13</span>'])),
          (done: true, at: DateTime(2026, 10, 4, 23, 13)));
    });

    test('an attempt still in progress is not done; the newest finished one counts', () {
      expect(parseQuizSubmission(quizPage(states: ['In progress'])).done, isFalse);
      expect(
          parseQuizSubmission(quizPage(states: [
            'Finished<span class="statedetails">Submitted 2026-10-04 23:13</span>',
            'Finished<span class="statedetails">Submitted 2026-10-05 08:02</span>',
            'Never submitted',
          ])).at,
          DateTime(2026, 10, 5, 8, 2));
    });

    test('another page is a ParseError', () {
      expect(() => parseQuizSubmission('<html><body id="page-site-index"></body></html>'),
          throwsA(isA<ParseError>()));
    });
  });

  group('refresh', () {
    test('assignments and quizzes are checked on their own pages; others are not', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.deadlines = [
        item(DeadlineKind.assignment, 1),
        item(DeadlineKind.quiz, 2),
        Deadline(
            title: 'Video 7', courseName: 'Multimedia Computing', kind: DeadlineKind.vod,
            end: DateTime(2026, 10, 25), moduleId: 3),
      ];
      eclass.submissions = {1: (done: true, at: DateTime(2026, 10, 21, 21, 14))};
      await data.refreshEclass();
      expect(eclass.submissionChecks, unorderedEquals([1, 2]));
      final byId = {for (final d in data.deadlines.data!.value) d.moduleId: d};
      expect(byId[1]!.done, isTrue);
      expect(byId[1]!.doneAt, DateTime(2026, 10, 21, 21, 14));
      expect(byId[2]!.done, isFalse);
      expect(byId[3]!.done, isFalse);
    });

    test('a page that fails keeps what was known, and the rest still refresh', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.deadlines = [item(DeadlineKind.assignment, 1), item(DeadlineKind.assignment, 2)];
      eclass.submissions = {1: (done: true, at: DateTime(2026, 10, 21))};
      await data.refreshEclass();
      eclass.failing = {1, 2};
      await data.refreshEclass();
      expect(data.deadlines.error, isNull);
      expect(data.deadlines.data!.value.map((d) => d.done), [true, false]);
    });

    test('the done state survives the cache', () async {
      final d = Deadline.fromJson(item(DeadlineKind.quiz, 9, done: true, doneAt: DateTime(2026, 10, 4, 23, 13)).toJson());
      expect(d.done, isTrue);
      expect(d.doneAt, DateTime(2026, 10, 4, 23, 13));
      final old = Deadline.fromJson(item(DeadlineKind.quiz, 9).toJson()..remove('done')..remove('doneAt'));
      expect(old.done, isFalse);
    });
  });

  test('submitted work leaves Needs attention and gets no reminders', () {
    final now = DateTime(2026, 10, 24, 9);
    final open = item(DeadlineKind.assignment, 1);
    final handedIn = item(DeadlineKind.assignment, 2, done: true);
    expect(needsAttention([open, handedIn], const [], now), [open]);
    final keys = planNotifications(now: now, deadlines: [open, handedIn]).map((n) => n.key);
    expect(keys.every((k) => k.startsWith(reminderStem(open))), isTrue);
    expect(keys, isNotEmpty);
  });
}
