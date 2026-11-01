// Port of test/timetable_parser_test.dart. The fixtures are real public replies
// from iut.edupage.org (timetable 145, "Fall_2026"), saved 2026-10-22.
import { describe, test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './setup.ts';
import { NetworkError, ParseError } from '../src/core/errors.ts';
import type { HttpRequest, HttpResponse } from '../src/core/http.ts';
import type { Lesson } from '../src/core/models.ts';
import { chooseTtNum, classGroupsIn, parseLessons, parseTables, UnknownClassGroup } from '../src/services/edupage/parser.ts';
import { EdupageClient } from '../src/services/edupage/client.ts';

const regulartt = fixture('edupage_regulartt.json');
const ttviewer = fixture('edupage_ttviewer.json');

const l = (weekday: number, start: string, end: string, subject: string, room: string, teacher: string): Lesson => ({
  weekday,
  start,
  end,
  subject,
  room,
  teacher,
  kind: '',
});

const ai = 'Artificial Intelligence';
const dlcv = 'Deep Learning for Computer Vision';
const mc = 'Multimedia Computing';
const esd = 'Embedded Software & Design';
const bda = 'Big Data Analytics';
const mental = 'Mental Education';
const [mon, tue, wed, thu, fri] = [1, 2, 3, 4, 5];

/** What `python scripts/pull_timetable.py --check --json` (study repo) printed for ICE23-1 on 2026-10-22. It drops Big Data Analytics (BDA) by default. */
const python = [
  l(mon, '13:00', '14:30', ai, 'B101 Conf', 'O.Eraliev'),
  l(mon, '14:30', '16:00', dlcv, 'B101 Conf', 'J.Hong'),
  l(tue, '09:30', '11:00', mc, 'B101 Conf', 'U.A.Minhaz'),
  l(wed, '13:00', '14:30', mc, 'B101 Conf', 'U.A.Minhaz'),
  l(wed, '15:00', '16:30', esd, 'B101 Conf', 'J.Hong'),
  l(thu, '11:00', '12:00', mental, 'B304 Conf', ''),
  l(thu, '12:00', '13:30', dlcv, 'B101 Conf', 'J.Hong'),
  l(thu, '14:00', '15:30', ai, 'B101 Conf', 'O.Eraliev'),
  l(fri, '14:00', '15:30', esd, 'B202', 'J.Hong'),
];

/** The same with `--all`: the whole group's timetable, Big Data included. */
const pythonAll = [
  python[0],
  python[1],
  python[2],
  l(tue, '12:30', '14:00', bda, 'B101 Conf', 'J.S.Lee'),
  python[3],
  python[4],
  python[5],
  python[6],
  python[7],
  l(fri, '10:30', '12:00', bda, 'B101 Conf', 'J.S.Lee'),
  python[8],
];

type Row = Record<string, unknown>;

/** A tiny hand-made `regularttGetData` body: 30-minute periods from 08:00. */
function body(opts: { lessons: Row[]; cards: Row[]; firstStart?: string }) {
  const t = (minutes: number) =>
    `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
  const periods = [];
  for (let i = 1; i <= 8; i++) {
    periods.push({ id: `${i}`, period: `${i}`, starttime: i === 1 ? (opts.firstStart ?? '08:00') : t(450 + 30 * i), endtime: t(480 + 30 * i) });
  }
  return {
    r: {
      dbiAccessorRes: {
        tables: [
          { id: 'periods', data_rows: periods },
          { id: 'classes', data_rows: [{ id: 'c1', name: 'G1' }, { id: 'c2', name: 'G2' }] },
          {
            id: 'subjects',
            data_rows: [
              { id: 's1', name: 'Signals', short: 'SIG' },
              { id: 's2', name: 'Other group only', short: 'OGO' },
            ],
          },
          { id: 'teachers', data_rows: [{ id: 't1', short: 'A.Kim' }, { id: 't2', short: 'B.Lee' }] },
          {
            id: 'classrooms',
            data_rows: [
              { id: 'r1', name: 'A101 (40)', short: 'A101' },
              { id: 'r2', name: 'A102 (40)', short: 'A102' },
            ],
          },
          { id: 'lessons', data_rows: opts.lessons },
          { id: 'cards', data_rows: opts.cards },
        ],
      },
    },
  };
}

const lesson = (id: string, o: { subject?: string; klass?: string; duration?: unknown } = {}): Row => ({
  id,
  subjectid: o.subject ?? 's1',
  teacherids: ['t1'],
  classids: [o.klass ?? 'c1'],
  ...(o.duration === undefined ? {} : { durationperiods: o.duration }),
});

const card = (lessonId: string, period: string, days: string, rooms = ['r1']): Row => ({
  id: `k${lessonId}${period}${days}`,
  lessonid: lessonId,
  period,
  days,
  classroomids: rooms,
});

describe('chooseTtNum', () => {
  test('fixture: default_num is blank, so the newest visible timetable', () => {
    assert.equal(JSON.parse(ttviewer).r.regular.default_num, '');
    assert.equal(chooseTtNum(JSON.parse(ttviewer)), '145');
    assert.equal(chooseTtNum(ttviewer), '145', 'raw JSON text works too');
  });

  const viewer = (defaultNum: string, tts: Row[]) => ({ r: { regular: { default_num: defaultNum, timetables: tts } } });
  const tt = (num: string, year: number, hidden = false) => ({ tt_num: num, year, text: `T${num}`, hidden });

  test('a visible default_num wins', () => {
    assert.equal(chooseTtNum(viewer('140', [tt('140', 2025), tt('145', 2026)])), '140');
  });

  test('a hidden or unknown default_num falls back to the newest', () => {
    assert.equal(chooseTtNum(viewer('150', [tt('145', 2026), tt('150', 2027, true)])), '145');
    assert.equal(chooseTtNum(viewer('999', [tt('145', 2026), tt('139', 2025)])), '145');
  });

  test('newest = highest year, then highest numeric tt_num, first on a tie', () => {
    assert.equal(chooseTtNum(viewer('', [tt('200', 2025), tt('9', 2026), tt('12', 2026)])), '12');
    assert.equal(chooseTtNum(viewer('', [tt('x', 2026), tt('y', 2026)])), 'x');
  });

  test('no visible timetable is a ParseError', () => {
    assert.throws(() => chooseTtNum(viewer('1', [tt('1', 2026, true)])), ParseError);
    assert.throws(() => chooseTtNum({ e: 'Error: bad args' }), ParseError);
  });
});

describe('ICE23-1 from the real fixture', () => {
  const data = JSON.parse(regulartt);

  test('minus Big Data matches the Python script row for row', () => {
    assert.deepEqual(parseLessons(data, 'ICE23-1', ['Big Data']), python);
  });

  test('with nothing excluded it is the whole group (Python --all)', () => {
    const got = parseLessons(data, 'ICE23-1');
    assert.deepEqual(got, pythonAll);
    assert.equal(got.filter((x) => x.subject === bda).length, 2);
  });

  test('excludeSubjects matches names case-insensitively, or the short code', () => {
    for (const ex of [['big data'], ['BDA'], ['Analytics', '']]) {
      assert.deepEqual(parseLessons(data, 'ICE23-1', ex), python, `${ex}`);
    }
    // A blank entry must not exclude everything.
    assert.equal(parseLessons(data, 'ICE23-1', [' ']).length, 11);
  });

  test('unplaced cards (empty period/days) are skipped', () => {
    const tables = parseTables(data);
    const ice = tables['classes'].find((c) => c['name'] === 'ICE23-1')!['id'];
    const mine = new Set(tables['lessons'].filter((x) => (x['classids'] as unknown[]).includes(ice)).map((x) => x['id']));
    const cards = tables['cards'].filter((c) => mine.has(c['lessonid']));
    const unplaced = cards.filter((c) => c['period'] === '' && c['days'] === '');
    // The fixture really has them: one spare card per lesson, 6 lessons.
    assert.equal(unplaced.length, 6);
    assert.equal(cards.length, 17);
    assert.equal(parseLessons(data, 'ICE23-1').length, cards.length - unplaced.length);
  });

  test('Mental Education spans 2 periods: 11:00 to the end of period 8', () => {
    const m = parseLessons(data, 'ICE23-1').filter((x) => x.subject === mental);
    assert.equal(m.length, 1);
    assert.equal(m[0].weekday, thu);
    assert.deepEqual([m[0].start, m[0].end], ['11:00', '12:00']);
    assert.equal(m[0].teacher, '', 'the lesson has no teacher');
    // 3-period lessons, for contrast.
    assert.equal(parseLessons(data, 'ICE23-1')[0].end, '14:30');
  });

  test('rooms are short names, sorted by weekday then start', () => {
    const got = parseLessons(data, 'ICE23-1');
    assert.deepEqual(new Set(got.map((x) => x.room)), new Set(['B101 Conf', 'B202', 'B304 Conf']));
    for (let i = 1; i < got.length; i++) {
      const a = got[i - 1], b = got[i];
      assert.ok(a.weekday < b.weekday || (a.weekday === b.weekday && a.start < b.start));
    }
  });

  test('another group comes out too, and an unknown one throws', () => {
    assert.ok(parseLessons(data, 'CSE23-1').length > 0);
    assert.throws(
      () => parseLessons(data, 'ICE99-9'),
      (e: unknown) => e instanceof UnknownClassGroup && e.available.includes('ICE23-1'),
    );
  });

  test('class groups are all 82 names, sorted', () => {
    const names = classGroupsIn(parseTables(data));
    assert.equal(names.length, 82);
    assert.ok(names.includes('ICE23-1'));
    assert.equal(names[0], 'AI25-1');
    assert.equal(names[names.length - 1], 'SBL(L)26-6');
    assert.deepEqual(names, [...names].sort());
  });
});

describe('synthetic data', () => {
  test('an unplaced card is skipped, a placed one kept', () => {
    const got = parseLessons(
      body({
        lessons: [lesson('a', { duration: 3 })],
        cards: [
          card('a', '', ''), // unplaced
          card('a', '3', '00000'), // has a period but no day
          card('a', '', '01000'), // has a day but no period
          card('a', '2', '01000'),
        ],
      }),
      'G1',
    );
    assert.deepEqual(got, [l(tue, '08:30', '10:00', 'Signals', 'A101', 'A.Kim')]);
  });

  test('durationperiods sets the end; missing means 1 period', () => {
    const got = parseLessons(
      body({
        lessons: [lesson('two', { duration: 2 }), lesson('one'), lesson('str', { duration: '2' })],
        cards: [card('two', '1', '10000'), card('one', '4', '10000'), card('str', '6', '10000')],
      }),
      'G1',
    );
    assert.deepEqual(got.map((x) => `${x.start}-${x.end}`), ['08:00-09:00', '09:30-10:00', '10:30-11:30']);
  });

  test('a lesson running past the last period is dropped', () => {
    const got = parseLessons(body({ lessons: [lesson('a', { duration: 3 })], cards: [card('a', '7', '10000')] }), 'G1');
    assert.deepEqual(got, []);
  });

  test('a card on several days gives one block per day; rooms are joined', () => {
    const got = parseLessons(
      body({ lessons: [lesson('a', { duration: 2 })], cards: [card('a', '5', '10101', ['r1', 'r2'])] }),
      'G1',
    );
    assert.deepEqual(got.map((x) => x.weekday), [mon, wed, fri]);
    assert.deepEqual(new Set(got.map((x) => x.room)), new Set(['A101, A102']));
  });

  test("other groups' lessons are ignored; unknown ids fall back like Python", () => {
    const got = parseLessons(
      body({
        lessons: [
          lesson('mine', { duration: 1 }),
          lesson('theirs', { subject: 's2', klass: 'c2', duration: 1 }),
          { ...lesson('ghost', { subject: 'nope', duration: 1 }), teacherids: ['t9'] },
        ],
        cards: [card('mine', '1', '10000'), card('theirs', '1', '10000'), card('ghost', '2', '10000', ['r9'])],
      }),
      'G1',
    );
    assert.deepEqual(got, [l(mon, '08:00', '08:30', 'Signals', 'A101', 'A.Kim'), l(mon, '08:30', '09:00', '?', 'r9', 't9')]);
  });

  test('sorted by weekday then start, identical blocks collapsed', () => {
    const got = parseLessons(
      body({
        lessons: [lesson('a', { duration: 1 })],
        cards: [
          card('a', '4', '00100'),
          card('a', '1', '00100'),
          card('a', '6', '10000'),
          card('a', '1', '00100'), // the same block twice
        ],
      }),
      'G1',
    );
    assert.deepEqual(got.map((x) => `${x.weekday} ${x.start}`), ['1 10:30', '3 08:00', '3 09:30']);
  });

  test('unpadded times are padded', () => {
    const got = parseLessons(
      body({ lessons: [lesson('a', { duration: 2 })], cards: [card('a', '1', '10000')], firstStart: '8:00' }),
      'G1',
    );
    assert.deepEqual([got[0].start, got[0].end], ['08:00', '09:00']);
  });

  test('a reply without tables is a ParseError', () => {
    assert.throws(() => parseLessons({ r: {} }, 'G1'), ParseError);
    assert.throws(() => parseLessons('not json', 'G1'), ParseError);
  });
});

/** Answers like iut.edupage.org from the fixtures, recording each request. */
class FakeEdupage {
  calls: { method: string; url: string; req: HttpRequest }[] = [];
  bodies: unknown[] = [];
  ttviewer = ttviewer;
  status = 200;

  http = async (url: string, req: HttpRequest = {}): Promise<HttpResponse> => {
    const method = req.method ?? (req.body == null ? 'GET' : 'POST');
    this.calls.push({ method, url, req });
    this.bodies.push(typeof req.body === 'string' && req.body ? JSON.parse(req.body) : null);
    let text = '<html></html>';
    let status = 200;
    if (method === 'POST') {
      const func = new URL(url).searchParams.get('__func');
      text = func === 'getTTViewerData' ? this.ttviewer : func === 'regularttGetData' ? regulartt : '{"e":"unknown"}';
      status = this.status;
    }
    if (status >= 500) throw new NetworkError(`answered ${status}`, status);
    const bytes = new TextEncoder().encode(text);
    return { status, url, redirected: false, headers: new Headers(), bytes, text: () => text };
  };
}

describe('EdupageClient', () => {
  let server: FakeEdupage;
  let client: EdupageClient;

  beforeEach(() => {
    server = new FakeEdupage();
    client = new EdupageClient({ http: server.http });
  });

  test("lessons(): warm-up GET, then the two RPCs with the script's bodies, no cookies", async () => {
    assert.deepEqual(await client.lessons('ICE23-1', ['Big Data']), python);
    assert.deepEqual(
      server.calls.map((c) => `${c.method} ${c.url}`),
      [
        'GET https://iut.edupage.org/timetable/',
        'POST https://iut.edupage.org/timetable/server/ttviewer.js?__func=getTTViewerData',
        'POST https://iut.edupage.org/timetable/server/regulartt.js?__func=regularttGetData',
      ],
    );
    assert.deepEqual(server.bodies[1], { __args: [null, {}], __gsh: '00000000' });
    assert.deepEqual(server.bodies[2], { __args: [null, '145'], __gsh: '00000000' });
    assert.ok(server.calls.every((c) => c.req.credentials === 'omit'));
  });

  test('classGroups() lists the names; the warm-up happens once', async () => {
    assert.equal((await client.classGroups()).length, 82);
    await client.lessons('ICE23-1');
    assert.equal(server.calls.filter((c) => c.method === 'GET').length, 1);
  });

  test('a year is passed through', async () => {
    await new EdupageClient({ http: server.http, year: 2026 }).classGroups();
    assert.deepEqual(server.bodies[1], { __args: [null, 2026], __gsh: '00000000' });
  });

  test('a rejected RPC ({"e": ...}) is a ParseError', async () => {
    server.ttviewer = '{"e":"Error: bad args"}';
    await assert.rejects(client.lessons('ICE23-1'), ParseError);
  });

  test('an HTTP error status is a NetworkError', async () => {
    server.status = 404;
    await assert.rejects(client.lessons('ICE23-1'), (e: unknown) => e instanceof NetworkError && e.status === 404);
  });
});
