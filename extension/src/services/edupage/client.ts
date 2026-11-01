import { NetworkError, ParseError } from '../../core/errors.ts';
import { request } from '../../core/http.ts';
import type { Lesson } from '../../core/models.ts';
import { chooseTtNum, classGroupsIn, lessonsFor, parseTables, type EdupageTables } from './parser.ts';

/**
 * The public EduPage timetable at iut.edupage.org over its RPC endpoints
 * (docs/ENDPOINTS.md). No login, no cookies of the student's sent.
 *
 * Every call fetches fresh data (the whole university's timetable, about
 * 400 KB); caching is the caller's job. The app sends a Referer; fetch can't
 * (it is a forbidden header), and the RPCs answer without it.
 */
export class EdupageClient {
  readonly baseUrl: string;

  /**
   * School year sent to `getTTViewerData`, e.g. 2026. Usually leave it unset:
   * then the newest visible timetable is used, which survives the year rolling over.
   */
  readonly year: number | undefined;

  private readonly http: typeof request;

  /** The RPCs answer without it today, but the reference script (and the public page) load /timetable/ first. Once per client is enough. */
  private warmedUp = false;

  constructor(opts: { http?: typeof request; year?: number; baseUrl?: string } = {}) {
    this.http = opts.http ?? request;
    this.year = opts.year;
    this.baseUrl = opts.baseUrl ?? 'https://iut.edupage.org';
  }

  /** All weekly lessons for classGroup (e.g. "ICE23-1"), minus subjects matching excludeSubjects (dropped courses). */
  async lessons(classGroup: string, excludeSubjects: Iterable<string> = []): Promise<Lesson[]> {
    return lessonsFor(await this.tables(), classGroup, excludeSubjects);
  }

  /** One download for both: the class group's lessons (none when it is blank) and every group, for the picker. */
  async lessonsAndGroups(classGroup: string, excludeSubjects: Iterable<string> = []): Promise<{ lessons: Lesson[]; groups: string[] }> {
    const tables = await this.tables();
    return { lessons: classGroup ? lessonsFor(tables, classGroup, excludeSubjects) : [], groups: classGroupsIn(tables) };
  }

  /** Class groups EduPage knows, for the picker in Settings. */
  async classGroups(): Promise<string[]> {
    return classGroupsIn(await this.tables());
  }

  private async tables(): Promise<EdupageTables> {
    // The server rejects a bare [null]; with no year the second arg is {}.
    const viewer = await this.rpc('ttviewer.js', 'getTTViewerData', [null, this.year ?? {}]);
    const ttNum = chooseTtNum(viewer);
    return parseTables(await this.rpc('regulartt.js', 'regularttGetData', [null, ttNum]));
  }

  private async rpc(script: string, func: string, args: unknown[]): Promise<unknown> {
    if (!this.warmedUp) {
      // Only for the session cookie; the RPC decides. A failure here is not fatal.
      try {
        await this.http(`${this.baseUrl}/timetable/`, { credentials: 'omit' });
      } catch {
        // the RPC below reports the real problem, if there is one
      }
      this.warmedUp = true;
    }

    const res = await this.http(`${this.baseUrl}/timetable/server/${script}?__func=${func}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify({ __args: args, __gsh: '00000000' }),
      credentials: 'omit',
      timeoutMs: 60_000,
    });
    if (res.status !== 200) throw new NetworkError(`EduPage ${func} answered ${res.status}`, res.status);

    let body: unknown;
    try {
      body = JSON.parse(res.text());
    } catch {
      throw new ParseError(`EduPage ${func} reply`);
    }
    // A rejected call answers 200 with {"e": "Error: ..."} and no "r".
    if (body == null || typeof body !== 'object' || !('r' in body)) throw new ParseError(`EduPage ${func} reply`);
    return body;
  }
}
