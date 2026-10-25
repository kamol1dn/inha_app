import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/features/deadlines_screen.dart';

import 'fakes.dart';
import 'screens_test.dart' show show;

void main() {
  test('done work shows by default, and clearing the filters brings it back', () async {
    final (data, _, _, _, _) = await makeAppData();
    expect(data.prefs.showDone, isTrue);
    data.prefs.showDone = false;
    expect(data.prefs.showDone, isFalse);
    data.prefs.resetDeadlineFilters();
    expect(data.prefs.showDone, isTrue);
  });

  testWidgets('"Show done" is a ticked checkbox; tapping its line unticks it', (tester) async {
    final (data, _, _, _, _) = await makeAppData();
    await show(tester, data, const DeadlinesScreen());
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.text('Show done'));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(data.prefs.showDone, isFalse);
  });
}
