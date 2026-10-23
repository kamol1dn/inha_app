import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/ui/format/format.dart';

void main() {
  group('rowTitle', () {
    test('drops the event suffix and turns a kind tag before a number into a word', () {
      expect(rowTitle('[QUIZ] 2 Week 6 - 2% (Quiz closes)'), 'Quiz 2 Week 6 - 2%');
    });

    test('drops a kind tag before words', () {
      expect(rowTitle('[QUIZ] Midterm review (Quiz opens)'), 'Midterm review');
      expect(rowTitle('[VOD]  Week 7  lecture'), 'Week 7 lecture');
    });

    test("drops Moodle's other event suffixes", () {
      expect(rowTitle('Lab 5 is due'), 'Lab 5');
      expect(rowTitle('Essay draft (Assignment due)'), 'Essay draft');
      expect(rowTitle('Peer review (Workshop closes)'), 'Peer review');
      expect(rowTitle('Reading list (closes)'), 'Reading list');
    });

    test('leaves plain titles and other brackets alone', () {
      expect(rowTitle('Assignment 1'), 'Assignment 1');
      expect(rowTitle('Video 7'), 'Video 7');
      expect(rowTitle('Report (due Friday)'), 'Report (due Friday)');
      expect(rowTitle('Lab 3 [group work]'), 'Lab 3 [group work]');
      expect(rowTitle('[2026] Final project'), '[2026] Final project');
    });

    test('never empties a title', () {
      expect(rowTitle('[QUIZ] (Quiz closes)'), '[QUIZ] (Quiz closes)');
    });
  });
}
