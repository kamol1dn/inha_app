import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/absence.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:inha_app/ui/theme/status_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040');
const esd = Course(id: 2615, name: 'Embedded Software & Design', code: 'SOC3050');
const dl = Course(id: 2626, name: 'Deep learning for computer vision', code: 'SOC4180');

CourseAttendance absences(Course c, int n) => CourseAttendance(course: c, classes: [
      for (var i = 0; i < n; i++)
        AttendanceEntry(date: DateTime(2026, 10, 1 + i), label: '${i + 1}Class', mark: AttendanceMark.absent),
      AttendanceEntry(date: DateTime(2026, 10, 20), label: '1Class', mark: AttendanceMark.present),
    ]);

void main() {
  group('AbsenceState', () {
    AbsenceState state(int used, int? limit) => AbsenceState(used, limit);

    test('no limit: raw count, no status, never a guessed limit', () {
      expect(state(3, null).status, isNull);
      expect(state(3, null).left, isNull);
      expect(state(3, null).line, '3 absences · limit not set');
      expect(state(1, null).line, '1 absence · limit not set');
    });

    test('warning at max(1, 25% of the allowance) left, danger at 0 or over', () {
      expect(state(2, 4).status, isNull); // 2 left of 4
      expect(state(3, 4).status, Status.warning); // 1 left
      expect(state(4, 4).status, Status.danger);
      expect(state(5, 4).status, Status.danger);
      expect(state(5, 8).status, isNull); // 3 left of 8
      expect(state(6, 8).status, Status.warning); // 2 left = 25%
      expect(state(1, 2).status, Status.warning); // 1 left: max(1, 0.5)
    });

    test('tags and lines (DESIGN.md 8)', () {
      expect(state(3, 4).tag, '1 left');
      expect(state(4, 4).tag, 'At limit');
      expect(state(5, 4).tag, 'Over limit');
      expect(state(1, 4).tag, isNull);
      expect(state(3, 4).line, '3 of 4 absences used');
      expect(state(5, 4).line, '5 absences · limit 4');
    });
  });

  test('troubleOrder: danger, warning, then timetable order', () {
    final limits = {ai.id: 6, esd.id: 5, dl.id: 8};
    final lessons = const [
      Lesson(weekday: 4, start: '12:00', end: '13:30', subject: 'Deep Learning for Computer Vision'),
      Lesson(weekday: 1, start: '14:00', end: '15:30', subject: 'Embedded Software & Design'),
      Lesson(weekday: 1, start: '09:00', end: '10:30', subject: 'Multimedia Computing'),
    ];
    const mmc = Course(id: 1, name: 'Multimedia Computing', code: '');
    final order = troubleOrder(
        [absences(dl, 3), absences(mmc, 0), absences(esd, 4), absences(ai, 6)], limits, lessons);
    expect(order.map((c) => c.course.name), [
      'Artificial Intelligence', // 6 of 6: danger
      'Embedded Software & Design', // 1 left: warning
      'Multimedia Computing', // Mon 09:00
      'Deep learning for computer vision', // Thu 12:00
    ]);
  });

  group('limits in preferences', () {
    test('set, change, clear; read back by the notifier from the same key', () async {
      final (data, _, _, _, _) = await makeAppData();
      data.setAbsenceLimit(ai.id, 6);
      data.setAbsenceLimit(esd.id, 4);
      data.setAbsenceLimit(esd.id, 5);
      expect(data.prefs.absenceLimits, {ai.id: 6, esd.id: 5});
      data.setAbsenceLimit(ai.id, null);
      expect(data.prefs.absenceLimits, {esd.id: 5});
      expect(Notifier.readAbsenceLimits(await SharedPreferences.getInstance()), {esd.id: 5});
    });

    test('an unreadable value is no limits', () async {
      final (data, _, _, _, _) = await makeAppData(prefs: {Notifier.absenceLimitsKey: '[1,2'});
      expect(data.prefs.absenceLimits, isEmpty);
    });
  });

  group('absence notification', () {
    final now = DateTime(2026, 10, 22, 12);
    final att = [
      CourseAttendance(course: esd, classes: [
        AttendanceEntry(date: DateTime(2026, 10, 14), label: '4Class', mark: AttendanceMark.absent),
        AttendanceEntry(date: DateTime(2026, 10, 21), label: '3Class', mark: AttendanceMark.absent),
      ]),
    ];
    String body(Map<int, int> limits) =>
        planNotifications(now: now, attendance: att, absenceLimits: limits).last.body;

    test('says how many are left once a limit is set', () {
      expect(body({}), endsWith('2 absences in this course so far.'));
      expect(body({esd.id: 4}), endsWith('2 of 4 allowed absences used, 2 left.'));
      expect(body({esd.id: 2}), endsWith('2 of 2 allowed absences used, none left.'));
      expect(body({esd.id: 1}), endsWith('2 absences, over the limit of 1.'));
    });
  });
}
