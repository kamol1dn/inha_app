import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/edupage/edupage_client.dart';
import 'package:inha_app/services/edupage/timetable_parser.dart';

/// Fixtures are real public replies from iut.edupage.org (timetable 145,
/// "Fall_2026"), saved 2026-10-22.
final _regulartt = File('test/fixtures/edupage_regulartt.json').readAsStringSync();
final _ttviewer = File('test/fixtures/edupage_ttviewer.json').readAsStringSync();

Lesson _l(int weekday, String start, String end, String subject, String room, String teacher) =>
    Lesson(weekday: weekday, start: start, end: end, subject: subject, room: room, teacher: teacher);

const _ai = 'Artificial Intelligence';
const _dlcv = 'Deep Learning for Computer Vision';
const _mc = 'Multimedia Computing';
const _esd = 'Embedded Software & Design';
const _bda = 'Big Data Analytics';
const _mental = 'Mental Education';

/// What `python scripts/pull_timetable.py --check --json` (study repo) printed
/// for ICE23-1 on 2026-10-22, against the same data as the fixture. The script
/// drops Big Data Analytics (short code BDA) by default.
final _python = [
  _l(DateTime.monday, '13:00', '14:30', _ai, 'B101 Conf', 'O.Eraliev'),
  _l(DateTime.monday, '14:30', '16:00', _dlcv, 'B101 Conf', 'J.Hong'),
  _l(DateTime.tuesday, '09:30', '11:00', _mc, 'B101 Conf', 'U.A.Minhaz'),
  _l(DateTime.wednesday, '13:00', '14:30', _mc, 'B101 Conf', 'U.A.Minhaz'),
  _l(DateTime.wednesday, '15:00', '16:30', _esd, 'B101 Conf', 'J.Hong'),
  _l(DateTime.thursday, '11:00', '12:00', _mental, 'B304 Conf', ''),
  _l(DateTime.thursday, '12:00', '13:30', _dlcv, 'B101 Conf', 'J.Hong'),
  _l(DateTime.thursday, '14:00', '15:30', _ai, 'B101 Conf', 'O.Eraliev'),
  _l(DateTime.friday, '14:00', '15:30', _esd, 'B202', 'J.Hong'),
];

/// The same with `--all`: the whole group's timetable, Big Data included.
final _pythonAll = [
  _python[0],
  _python[1],
  _python[2],
  _l(DateTime.tuesday, '12:30', '14:00', _bda, 'B101 Conf', 'J.S.Lee'),
  _python[3],
  _python[4],
  _python[5],
  _python[6],
  _python[7],
  _l(DateTime.friday, '10:30', '12:00', _bda, 'B101 Conf', 'J.S.Lee'),
  _python[8],
];

List<Map<String, dynamic>> _json(List<Lesson> ls) => [for (final l in ls) l.toJson()];

/// A tiny hand-made `regularttGetData` body: 30-minute periods from 08:00.
Map<String, dynamic> _body({
  required List<Map<String, dynamic>> lessons,
  required List<Map<String, dynamic>> cards,
  String firstStart = '08:00',
}) {
  String t(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  return {
    'r': {
      'dbiAccessorRes': {
        'tables': [
          {
            'id': 'periods',
            'data_rows': [
              for (var i = 1; i <= 8; i++)
                {
                  'id': '$i',
                  'period': '$i',
                  'starttime': i == 1 ? firstStart : t(450 + 30 * i),
                  'endtime': t(480 + 30 * i),
                },
            ],
          },
          {
            'id': 'classes',
            'data_rows': [
              {'id': 'c1', 'name': 'G1'},
              {'id': 'c2', 'name': 'G2'},
            ],
          },
          {
            'id': 'subjects',
            'data_rows': [
              {'id': 's1', 'name': 'Signals', 'short': 'SIG'},
              {'id': 's2', 'name': 'Other group only', 'short': 'OGO'},
            ],
          },
          {
            'id': 'teachers',
            'data_rows': [
              {'id': 't1', 'short': 'A.Kim'},
              {'id': 't2', 'short': 'B.Lee'},
            ],
          },
          {
            'id': 'classrooms',
            'data_rows': [
              {'id': 'r1', 'name': 'A101 (40)', 'short': 'A101'},
              {'id': 'r2', 'name': 'A102 (40)', 'short': 'A102'},
            ],
          },
          {'id': 'lessons', 'data_rows': lessons},
          {'id': 'cards', 'data_rows': cards},
        ],
      },
    },
  };
}

Map<String, dynamic> _lesson(String id, {String subject = 's1', String klass = 'c1', Object? duration}) => {
      'id': id,
      'subjectid': subject,
      'teacherids': ['t1'],
      'classids': [klass],
      'durationperiods': ?duration,
    };

Map<String, dynamic> _card(String lessonId, String period, String days, {List<String> rooms = const ['r1']}) =>
    {'id': 'k$lessonId$period$days', 'lessonid': lessonId, 'period': period, 'days': days, 'classroomids': rooms};

void main() {
  group('chooseTtNum', () {
    test('fixture: default_num is blank, so the newest visible timetable', () {
      expect(jsonDecode(_ttviewer)['r']['regular']['default_num'], '');
      expect(chooseTtNum(jsonDecode(_ttviewer)), '145');
      expect(chooseTtNum(_ttviewer), '145', reason: 'raw JSON text works too');
    });

    Map<String, dynamic> viewer(String defaultNum, List<Map<String, dynamic>> tts) => {
          'r': {
            'regular': {'default_num': defaultNum, 'timetables': tts},
          },
        };
    Map<String, dynamic> tt(String num, int year, {bool hidden = false}) =>
        {'tt_num': num, 'year': year, 'text': 'T$num', 'hidden': hidden};

    test('a visible default_num wins', () {
      expect(chooseTtNum(viewer('140', [tt('140', 2025), tt('145', 2026)])), '140');
    });

    test('a hidden or unknown default_num falls back to the newest', () {
      expect(chooseTtNum(viewer('150', [tt('145', 2026), tt('150', 2027, hidden: true)])), '145');
      expect(chooseTtNum(viewer('999', [tt('145', 2026), tt('139', 2025)])), '145');
    });

    test('newest = highest year, then highest numeric tt_num, first on a tie', () {
      expect(chooseTtNum(viewer('', [tt('200', 2025), tt('9', 2026), tt('12', 2026)])), '12');
      expect(chooseTtNum(viewer('', [tt('x', 2026), tt('y', 2026)])), 'x');
    });

    test('no visible timetable is a ParseError', () {
      expect(() => chooseTtNum(viewer('1', [tt('1', 2026, hidden: true)])), throwsA(isA<ParseError>()));
      expect(() => chooseTtNum({'e': 'Error: bad args'}), throwsA(isA<ParseError>()));
    });
  });

  group('ICE23-1 from the real fixture', () {
    final data = jsonDecode(_regulartt);

    test('minus Big Data matches the Python script row for row', () {
      final got = parseLessons(data, 'ICE23-1', excludeSubjects: {'Big Data'});
      expect(_json(got), _json(_python));
    });

    test('with nothing excluded it is the whole group (Python --all)', () {
      final got = parseLessons(data, 'ICE23-1');
      expect(_json(got), _json(_pythonAll));
      expect(got.where((l) => l.subject == _bda), hasLength(2));
    });

    test('excludeSubjects matches names case-insensitively, or the short code', () {
      for (final ex in [
        {'big data'},
        {'BDA'},
        {'Analytics', ''},
      ]) {
        final got = parseLessons(data, 'ICE23-1', excludeSubjects: ex);
        expect(_json(got), _json(_python), reason: '$ex');
      }
      // A blank entry must not exclude everything.
      expect(parseLessons(data, 'ICE23-1', excludeSubjects: {' '}), hasLength(11));
    });

    test('unplaced cards (empty period/days) are skipped', () {
      final tables = parseTables(data);
      final ice = tables['classes']!.firstWhere((c) => c['name'] == 'ICE23-1')['id'];
      final mine = {
        for (final l in tables['lessons']!)
          if ((l['classids'] as List).contains(ice)) l['id'],
      };
      final cards = tables['cards']!.where((c) => mine.contains(c['lessonid'])).toList();
      final unplaced = cards.where((c) => c['period'] == '' && c['days'] == '').toList();
      // The fixture really has them: one spare card per lesson, 6 lessons.
      expect(unplaced, hasLength(6));
      expect(cards, hasLength(17));
      expect(parseLessons(data, 'ICE23-1'), hasLength(cards.length - unplaced.length));
    });

    test('Mental Education spans 2 periods: 11:00 to the end of period 8', () {
      final mental = parseLessons(data, 'ICE23-1').where((l) => l.subject == _mental).toList();
      expect(mental, hasLength(1));
      expect(mental.single.weekday, DateTime.thursday);
      expect((mental.single.start, mental.single.end), ('11:00', '12:00'));
      expect(mental.single.teacher, '', reason: 'the lesson has no teacher');
      // 3-period lessons, for contrast.
      expect(parseLessons(data, 'ICE23-1').first.end, '14:30');
    });

    test('rooms are short names, sorted by weekday then start', () {
      final got = parseLessons(data, 'ICE23-1');
      expect(got.map((l) => l.room).toSet(), {'B101 Conf', 'B202', 'B304 Conf'});
      for (var i = 1; i < got.length; i++) {
        final a = got[i - 1], b = got[i];
        expect(a.weekday < b.weekday || (a.weekday == b.weekday && a.start.compareTo(b.start) < 0), isTrue);
      }
    });

    test('another group comes out too, and an unknown one throws', () {
      expect(parseLessons(data, 'CSE23-1'), isNotEmpty);
      expect(
        () => parseLessons(data, 'ICE99-9'),
        throwsA(isA<UnknownClassGroup>().having((e) => e.available, 'available', contains('ICE23-1'))),
      );
    });

    test('class groups are all 82 names, sorted', () {
      final names = classGroupsIn(parseTables(data));
      expect(names, hasLength(82));
      expect(names, contains('ICE23-1'));
      expect(names.first, 'AI25-1');
      expect(names.last, 'SBL(L)26-6');
      expect(names, [...names]..sort());
    });
  });

  group('synthetic data', () {
    test('an unplaced card is skipped, a placed one kept', () {
      final got = parseLessons(
          _body(lessons: [
            _lesson('a', duration: 3),
          ], cards: [
            _card('a', '', ''), // unplaced
            _card('a', '3', '00000'), // has a period but no day
            _card('a', '', '01000'), // has a day but no period
            _card('a', '2', '01000'),
          ]),
          'G1');
      expect(_json(got), _json([_l(DateTime.tuesday, '08:30', '10:00', 'Signals', 'A101', 'A.Kim')]));
    });

    test('durationperiods sets the end; missing means 1 period', () {
      final got = parseLessons(
          _body(lessons: [
            _lesson('two', duration: 2),
            _lesson('one'),
            _lesson('str', duration: '2'),
          ], cards: [
            _card('two', '1', '10000'),
            _card('one', '4', '10000'),
            _card('str', '6', '10000'),
          ]),
          'G1');
      expect([for (final l in got) '${l.start}-${l.end}'], ['08:00-09:00', '09:30-10:00', '10:30-11:30']);
    });

    test('a lesson running past the last period is dropped', () {
      final got = parseLessons(
          _body(lessons: [_lesson('a', duration: 3)], cards: [_card('a', '7', '10000')]), 'G1');
      expect(got, isEmpty);
    });

    test('a card on several days gives one block per day; rooms are joined', () {
      final got = parseLessons(
          _body(lessons: [
            _lesson('a', duration: 2),
          ], cards: [
            _card('a', '5', '10101', rooms: ['r1', 'r2']),
          ]),
          'G1');
      expect(got.map((l) => l.weekday), [DateTime.monday, DateTime.wednesday, DateTime.friday]);
      expect(got.map((l) => l.room).toSet(), {'A101, A102'});
    });

    test('other groups\' lessons are ignored; unknown ids fall back like Python', () {
      final got = parseLessons(
          _body(lessons: [
            _lesson('mine', duration: 1),
            _lesson('theirs', subject: 's2', klass: 'c2', duration: 1),
            {..._lesson('ghost', subject: 'nope', duration: 1), 'teacherids': ['t9']},
          ], cards: [
            _card('mine', '1', '10000'),
            _card('theirs', '1', '10000'),
            _card('ghost', '2', '10000', rooms: ['r9']),
          ]),
          'G1');
      expect(_json(got), _json([
        _l(DateTime.monday, '08:00', '08:30', 'Signals', 'A101', 'A.Kim'),
        _l(DateTime.monday, '08:30', '09:00', '?', 'r9', 't9'),
      ]));
    });

    test('sorted by weekday then start, identical blocks collapsed', () {
      final got = parseLessons(
          _body(lessons: [
            _lesson('a', duration: 1),
          ], cards: [
            _card('a', '4', '00100'),
            _card('a', '1', '00100'),
            _card('a', '6', '10000'),
            _card('a', '1', '00100'), // the same block twice
          ]),
          'G1');
      expect([for (final l in got) '${l.weekday} ${l.start}'], ['1 10:30', '3 08:00', '3 09:30']);
    });

    test('unpadded times are padded', () {
      final got = parseLessons(
          _body(lessons: [_lesson('a', duration: 2)], cards: [_card('a', '1', '10000')], firstStart: '8:00'),
          'G1');
      expect((got.single.start, got.single.end), ('08:00', '09:00'));
    });

    test('a reply without tables is a ParseError', () {
      expect(() => parseLessons({'r': {}}, 'G1'), throwsA(isA<ParseError>()));
      expect(() => parseLessons('not json', 'G1'), throwsA(isA<ParseError>()));
    });
  });

  group('EdupageClient', () {
    late _FakeEdupage server;
    late EdupageClient client;

    setUp(() {
      server = _FakeEdupage();
      client = EdupageClient(Dio()..httpClientAdapter = server);
    });

    test('lessons(): warm-up GET, then the two RPCs with the script\'s bodies', () async {
      final got = await client.lessons('ICE23-1', excludeSubjects: {'Big Data'});
      expect(_json(got), _json(_python));

      expect(server.calls.map((c) => '${c.method} ${c.uri}'), [
        'GET https://iut.edupage.org/timetable/',
        'POST https://iut.edupage.org/timetable/server/ttviewer.js?__func=getTTViewerData',
        'POST https://iut.edupage.org/timetable/server/regulartt.js?__func=regularttGetData',
      ]);
      expect(server.bodies[1], {
        '__args': [null, {}],
        '__gsh': '00000000',
      });
      expect(server.bodies[2], {
        '__args': [null, '145'],
        '__gsh': '00000000',
      });
      expect(server.calls[1].headers['Referer'], 'https://iut.edupage.org/timetable/');
    });

    test('classGroups() lists the names; the warm-up happens once', () async {
      expect(await client.classGroups(), hasLength(82));
      await client.lessons('ICE23-1');
      expect(server.calls.where((c) => c.method == 'GET'), hasLength(1));
    });

    test('a year is passed through', () async {
      await EdupageClient(Dio()..httpClientAdapter = server, year: 2026).classGroups();
      expect(server.bodies[1], {
        '__args': [null, 2026],
        '__gsh': '00000000',
      });
    });

    test('a rejected RPC ({"e": ...}) is a ParseError', () async {
      server.ttviewer = '{"e":"Error: bad args"}';
      await expectLater(client.lessons('ICE23-1'), throwsA(isA<ParseError>()));
    });

    test('an HTTP error status surfaces as a DioException', () async {
      server.status = 404;
      final lenient = Dio(BaseOptions(validateStatus: (c) => c != null && c < 500))
        ..httpClientAdapter = server;
      await expectLater(EdupageClient(lenient).lessons('ICE23-1'), throwsA(isA<DioException>()));
    });
  });
}

/// Answers like iut.edupage.org from the fixtures, recording each request.
class _FakeEdupage implements HttpClientAdapter {
  final calls = <RequestOptions>[];
  final bodies = <Object?>[];
  String ttviewer = _ttviewer;
  int status = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    final sent = requestStream == null ? const <int>[] : await requestStream.expand((c) => c).toList();
    bodies.add(sent.isEmpty ? null : jsonDecode(utf8.decode(sent)));

    if (options.method == 'GET') {
      return ResponseBody.fromString('<html></html>', 200, headers: {
        Headers.contentTypeHeader: ['text/html'],
      });
    }
    final text = switch (options.uri.queryParameters['__func']) {
      'getTTViewerData' => ttviewer,
      'regularttGetData' => _regulartt,
      _ => '{"e":"unknown"}',
    };
    return ResponseBody.fromString(text, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}
