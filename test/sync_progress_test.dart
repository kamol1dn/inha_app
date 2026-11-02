import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/data/sync_progress.dart';
import 'package:inha_app/features/common.dart';
import 'package:inha_app/models/models.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

const ai = Course(id: 2626, name: 'Artificial Intelligence', code: 'SOC4040');
const os = Course(id: 2627, name: 'Operating Systems', code: 'SOC3030');

/// eClass with its grades pages hanging until [release].
class SlowMarks extends FakeEclass {
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<CourseGrades> courseGrades(Course course) async {
    await _gate.future;
    return super.courseGrades(course);
  }
}

Future<(AppData, SlowMarks)> slowData() async {
  final (base, _, timetable, ins, mail) = await makeAppData();
  final eclass = SlowMarks()..courseList = const [ai, os];
  return (AppData(eclass: eclass, timetable: timetable, ins: ins, mail: mail, cache: base.cache, prefs: base.prefs), eclass);
}

void main() {
  group('SyncProgress', () {
    test('a step shows until it ends, and the count starts over after the last', () async {
      final sync = SyncProgress();
      expect(sync.active, isFalse);
      final gate = Completer<void>();
      final step = sync.step('eClass', 'course list', () => gate.future);
      expect(sync.active, isTrue);
      expect(sync.current, 'eClass: course list');
      expect((sync.done, sync.total), (0, 1));
      gate.complete();
      await step;
      expect(sync.active, isFalse);
      expect(sync.current, isNull);
      expect((sync.done, sync.total), (0, 0));
    });

    test('the longest wait is what it names; other services are listed once', () async {
      final sync = SyncProgress();
      final first = Completer<void>(), second = Completer<void>();
      final steps = [
        sync.step('eClass', 'marks for Algebra', () => first.future),
        sync.step('eClass', 'marks for Physics', () => second.future),
        sync.step('Mail', 'Inbox', () async {}),
        sync.step('INS', 'grades', () => Completer<void>().future),
      ];
      expect(sync.current, 'eClass: marks for Algebra');
      expect(sync.others, ['Mail', 'INS']);
      first.complete();
      await steps[0];
      expect(sync.current, 'eClass: marks for Physics');
      second.complete();
    });

    test('a step that fails still ends, and the error reaches the caller', () async {
      final sync = SyncProgress();
      await expectLater(sync.step<void>('INS', 'grades', () async => throw StateError('down')), throwsStateError);
      expect(sync.active, isFalse);
    });

    test('a span keeps the count across a gap between steps', () async {
      final sync = SyncProgress();
      await sync.span(() async {
        await sync.step('eClass', 'course list', () async {});
        expect(sync.active, isTrue);
        expect((sync.done, sync.total), (1, 1));
        final next = sync.step('eClass', 'marks for Algebra', () async {});
        expect((sync.done, sync.total), (1, 2));
        await next;
      });
      expect((sync.active, sync.total), (false, 0));
    });
  });

  group('refreshing', () {
    test('eClass names each course as it waits on it, and finishes clean', () async {
      final (data, eclass) = await slowData();
      final refresh = data.refreshEclass();
      await pumpEventQueue();
      expect(data.sync.current, 'eClass: marks for Artificial Intelligence');
      // The course list, the calendar pages (all courses, then each), the bell menu and both
      // attendance pages are done; both marks pages hang.
      expect((data.sync.done, data.sync.total), (7, 9));
      eclass.release();
      await refresh;
      expect(data.sync.active, isFalse);
      expect(data.courseGrades.data?.value.length, 2);
    });

    test('a failing service does not leave the strip behind', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.error = Exception('down');
      await data.refreshEclass();
      expect(data.sync.active, isFalse);
      expect(data.deadlines.error, isNotNull);
    });

    testWidgets('the strip says what it is doing, then goes away', (tester) async {
      late AppData data;
      late SlowMarks eclass;
      await tester.runAsync(() async => (data, eclass) = await slowData());
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: data,
        child: const MaterialApp(home: Scaffold(body: SyncStrip())),
      ));
      expect(find.byType(LinearProgressIndicator), findsNothing);

      late Future<void> refresh;
      await tester.runAsync(() async {
        refresh = data.refreshEclass();
        await pumpEventQueue();
      });
      await tester.pump();
      expect(find.text('eClass: marks for Artificial Intelligence'), findsOneWidget);
      expect(find.text('7 of 9'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.runAsync(() async {
        eclass.release();
        await refresh;
      });
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('eClass:'), findsNothing);
    });
  });
}
