import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/home_widgets.dart';
import 'package:inha_app/notifications/routes.dart';
import 'package:inha_app/notifications/rules.dart';

// Home-screen widget taps carry the keys notification taps do (docs/WIDGETS.md).
// The Kotlin side builds them in campus/TapKeys.kt; TapKeysTest.kt expects the
// same strings as this file.

void main() {
  final quiz = Deadline(
    title: '[QUIZ] 2 Week 6 - 2% (Quiz closes)',
    courseName: 'Artificial Intelligence[202602-AIE3010-001]',
    kind: DeadlineKind.quiz,
    end: DateTime.utc(2026, 10, 24, 18, 59), // 23:59 in Tashkent
    moduleId: 102,
  );
  const course = Course(id: 2622, name: 'Artificial Intelligence', code: 'AIE3010');

  test('reminderStem matches the Kotlin TapKeys', () {
    expect(reminderStem(quiz), 'due:quiz:artificial intelligence|[quiz] 2 week 6 - 2% (quiz closes)|20261024T1859Z');
  });

  group('widgetTapKey', () {
    test('reads the key from iut://open', () {
      final uri = Uri(scheme: 'iut', host: 'open', queryParameters: {'key': '${reminderStem(quiz)}|widget'});
      expect(widgetTapKey(uri), '${reminderStem(quiz)}|widget');
      expect(widgetTapKey(Uri.parse('iut://open?key=tab%3A3')), 'tab:3');
    });

    test('ignores anything else', () {
      expect(widgetTapKey(null), isNull);
      expect(widgetTapKey(Uri.parse('https://open?key=tab:3')), isNull);
      expect(widgetTapKey(Uri.parse('iut://open')), isNull);
      expect(widgetTapKey(Uri.parse('iut://other?key=tab:3')), isNull);
    });
  });

  group('widget keys route like notification keys', () {
    test('a deadline opens its sheet', () {
      final t = notificationTarget('${reminderStem(quiz)}|widget', deadlines: [quiz]);
      expect(t, isA<DeadlineTarget>().having((t) => t.deadline, 'deadline', quiz));
    });

    test('a course opens the course', () {
      final t = notificationTarget('absent:2622|widget', attendance: [const CourseAttendance(course: course)]);
      expect(t, isA<CourseTarget>().having((t) => t.course.id, 'id', 2622));
    });

    test('a class opens Schedule on its day', () {
      expect(notificationTarget('class:2026-10-26|widget'), isA<ScheduleTarget>().having((t) => t.weekday, 'weekday', 1));
    });

    test('tab keys open the tab', () {
      expect(notificationTarget('tab:0'), isA<TabTarget>().having((t) => t.tab, 'tab', 0));
      expect(notificationTarget('tab:3'), isA<TabTarget>().having((t) => t.tab, 'tab', 3));
      expect(notificationTarget('tab:9'), isNull);
      expect(notificationTarget('tab:x'), isNull);
    });
  });
}
