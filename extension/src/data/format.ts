// Every user-visible time and date string comes from here (DESIGN.md section 9).
// A port of lib/ui/format/format.dart; times are epoch ms or Dates.

const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

const pad = (n: number) => String(n).padStart(2, '0');
const asDate = (t: number | Date) => (typeof t === 'number' ? new Date(t) : t);

/** ISO weekday, 1 = Monday .. 7 = Sunday. */
export const isoWeekday = (t: Date) => ((t.getDay() + 6) % 7) + 1;

export const midnight = (t: number | Date) => {
  const d = asDate(t);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
};

/** Whole calendar days from `a` to `b`. */
export const daysBetween = (a: number | Date, b: number | Date) =>
  Math.round((midnight(b).getTime() - midnight(a).getTime()) / DAY);

/** 'YYYY-MM-DD' in local time. */
export const dayKey = (t: number | Date) => {
  const d = asDate(t);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

/** 'YYYY-MM-DD' to local midnight. */
export const fromDayKey = (k: string) => {
  const [y, m, d] = k.split('-').map(Number);
  return new Date(y, m - 1, d);
};

/** 09:00 */
export const clock = (t: number | Date) => {
  const d = asDate(t);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

/** Thu 23 Oct (year only when it isn't this year) */
export function dayDate(t: number | Date, now = new Date()): string {
  const d = asDate(t);
  const y = d.getFullYear() === now.getFullYear() ? '' : ` ${d.getFullYear()}`;
  return `${wd[isoWeekday(d) - 1]} ${d.getDate()} ${mon[d.getMonth()]}${y}`;
}

export const weekdayShort = (weekday: number) => wd[weekday - 1];

/** Today / Tomorrow / Sat 25 Oct, for day group headers. */
export function dayHeader(t: number | Date, now = new Date()): string {
  const days = daysBetween(now, t);
  if (days === 0) return 'Today';
  if (days === 1) return 'Tomorrow';
  if (days === -1) return 'Yesterday';
  return dayDate(t, now);
}

/** 1 h 10 min / 40 min */
export function duration(ms: number): string {
  const total = Math.floor(ms / MIN);
  const h = Math.floor(total / 60), m = total % 60;
  if (h === 0) return `${m} min`;
  if (m === 0) return `${h} h`;
  return `${h} h ${m} min`;
}

/** now / in 25 min / in 2 h 15 min / in 6 h / Sat 23:59 / 3 Nov 23:59 / Overdue 2 h */
export function relative(t: number, now = Date.now()): string {
  const d = t - now;
  if (d < 0) {
    const p = -d;
    if (p < DAY) return p < HOUR ? `Overdue ${Math.floor(p / MIN)} min` : `Overdue ${Math.floor(p / HOUR)} h`;
    return `Overdue ${Math.floor(p / DAY)} d`;
  }
  if (d < MIN) return 'now';
  if (d < HOUR) return `in ${Math.floor(d / MIN)} min`;
  if (d < 3 * HOUR) return `in ${duration(d)}`;
  if (d < DAY) return `in ${Math.floor(d / HOUR)} h`;
  const at = new Date(t);
  if (d < 7 * DAY) return `${wd[isoWeekday(at) - 1]} ${clock(at)}`;
  return `${at.getDate()} ${mon[at.getMonth()]} ${clock(at)}`;
}

/** For lists of past items (mail): 14:07 today, Wed 14:07 within the week, otherwise 17 Oct. */
export function pastWhen(t: number, now = new Date()): string {
  const at = new Date(t);
  const days = daysBetween(at, now);
  if (days <= 0) return clock(at);
  if (days < 7) return `${wd[isoWeekday(at) - 1]} ${clock(at)}`;
  return `${at.getDate()} ${mon[at.getMonth()]}${at.getFullYear() === now.getFullYear() ? '' : ` ${at.getFullYear()}`}`;
}

/** Thu 23 Oct 14:07 */
export const dayDateTime = (t: number | Date, now = new Date()) => `${dayDate(t, now)} ${clock(t)}`;

const kindTag = /^\[([A-Za-z]{2,12})\]\s*/;
const eventSuffix = /\s*(\((\w+\s+)?(opens|closes|is due|due|starts|ends)\)|\s+is due)\s*$/i;

/**
 * An eClass item's title as a row shows it (DESIGN.md 7): Moodle's event
 * suffix ("(Quiz closes)", "is due") is dropped, and so is a leading kind tag,
 * except that before a number it becomes a word, so
 * "[QUIZ] 2 Week 6 - 2% (Quiz closes)" reads "Quiz 2 Week 6 - 2%".
 */
export function rowTitle(title: string): string {
  let t = title.trim().replace(eventSuffix, '');
  const tag = kindTag.exec(t);
  if (tag) {
    const rest = t.slice(tag[0].length);
    const word = tag[1];
    t = /^\d/.test(rest) ? `${word[0].toUpperCase()}${word.slice(1).toLowerCase()} ${rest}` : rest;
  }
  t = t.replace(/\s+/g, ' ').trim();
  return t || title.trim();
}

/** Mon 26 – Fri 30 Oct */
export function dayRange(a: Date, b: Date, now = new Date()): string {
  if (a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth()) {
    return `${wd[isoWeekday(a) - 1]} ${a.getDate()} – ${dayDate(b, now)}`;
  }
  return `${dayDate(a, now)} – ${dayDate(b, now)}`;
}

/** 812 B / 14 KB / 2.3 MB / 18 MB */
export function fileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${Math.round(kb)} KB`;
  const mb = kb / 1024;
  return mb < 10 ? `${mb.toFixed(1)} MB` : `${Math.round(mb)} MB`;
}

/** 08:41 (today) / Tue 18:04 */
export function updatedAt(t: number, now = new Date()): string {
  const at = new Date(t);
  return daysBetween(at, now) === 0 ? clock(at) : `${wd[isoWeekday(at) - 1]} ${clock(at)}`;
}

/** "today 14:00", "tomorrow 13:00", "Mon 13:00": when a class on `day` is, from `now`. */
export function classWhen(day: number | Date, start: string, now: number | Date): string {
  const h = dayHeader(day, asDate(now));
  if (h === 'Today' || h === 'Tomorrow') return `${h.toLowerCase()} ${start}`;
  return `${wd[isoWeekday(asDate(day)) - 1]} ${start}`;
}

/** "09:00" to minutes after midnight, or null. */
export function parseHm(s: string): number | null {
  const m = /^\s*(\d{1,2}):(\d{2})/.exec(s);
  if (!m) return null;
  const h = Number(m[1]), min = Number(m[2]);
  return h > 23 || min > 59 ? null : h * 60 + min;
}

/** The lesson's start on the day of `on`. */
export function atTime(on: Date, hm: string): Date | null {
  const mins = parseHm(hm);
  if (mins == null) return null;
  return new Date(on.getFullYear(), on.getMonth(), on.getDate(), Math.floor(mins / 60), mins % 60);
}

export { MIN, HOUR, DAY };
