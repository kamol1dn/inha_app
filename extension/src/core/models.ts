// Plain data shared by every service and view. A port of lib/models/models.dart.
//
// Everything is JSON as it is, so the last good fetch can be cached in
// chrome.storage and shown offline. Times are epoch milliseconds; calendar
// days are 'YYYY-MM-DD' strings.

export type Service = 'eclass' | 'edupage' | 'ins' | 'mail';

export const serviceLabel: Record<Service, string> = {
  eclass: 'eClass',
  edupage: 'Timetable',
  ins: 'INS',
  mail: 'Mail',
};

/** An eClass course, e.g. "Multimedia Computing[202602-SOC4020-001]". */
export interface Course {
  id: number;
  name: string; // "Multimedia Computing"
  code: string; // "SOC4020"
  professor: string;
}

/**
 * Splits eClass's "Name[202602-SOC4020-001]" title. Anything after the
 * bracket is dropped too: the dashboard appends a "NEW" badge to some.
 */
export function courseFromTitle(id: number, title: string, professor = ''): Course {
  const m = /^(.*?)\s*\[\d+-([A-Z]+\d+)-\d+\][\s\S]*$/.exec(title.trim());
  return { id, name: (m?.[1] ?? title).trim(), code: m?.[2] ?? '', professor };
}

/** One timetable slot from EduPage. */
export interface Lesson {
  weekday: number; // 1 = Monday .. 5 = Friday
  start: string; // "09:00"
  end: string; // "10:30"
  subject: string;
  room: string;
  teacher: string;
  kind: string; // "Lecture", "Lab", ... or ''
}

/**
 * classPeriod is eClass's course-level "Course[001]-3교시" event: a scheduled
 * class period, not something due. Kept so it can be shown on request, but it
 * never counts as a deadline or triggers a reminder.
 */
export type DeadlineKind = 'assignment' | 'quiz' | 'vod' | 'other' | 'classPeriod';

/** An item from eClass's upcoming-events calendar. A VOD is a watch window (start..end). */
export interface Deadline {
  title: string;
  courseName: string;
  /** The eClass course, from the event's own link. Missing where the page gave none, and in an old cache. */
  courseId?: number | null;
  kind: DeadlineKind;
  start: number | null;
  end: number;
  moduleId: number | null; // for opening it
  moduleType: string | null; // "assign", "quiz", "vod", "ubboard", ...
  /** Handed in (assignment) or attempted (quiz), from the item's own page. False when unknown. */
  done: boolean;
  doneAt: number | null;
}

export type AttendanceMark = 'present' | 'absent' | 'late' | 'other' | 'unmarked';

export interface AttendanceEntry {
  date: string; // 'YYYY-MM-DD'
  label: string; // "3Class"
  mark: AttendanceMark;
}

/** One watchable VOD and how much of it has been watched. */
export interface VodProgress {
  week: number;
  title: string;
  lengthSec: number;
  percent: number; // 0..100
  /** The course module, for /mod/vod/view.php?id=<this>. Missing when the course's VOD list didn't name it, and in an old cache. */
  moduleId?: number | null;
  /** The watch window. Missing when the page gives none, and in an old cache. */
  opens?: number | null;
  closes?: number | null;
}

/** Everything attendance-related for one course. */
export interface CourseAttendance {
  course: Course;
  classes: AttendanceEntry[]; // empty if the course takes none
  vods: VodProgress[]; // empty if VODs are not progress-tracked
}

/** One course result from INS. letter is '-' while a course is not graded. */
export interface GradeRecord {
  term: string; // "2023 Fall Semester"
  termKey: number; // 20231, sortable
  code: string; // "SOC4020"
  name: string;
  credits: number;
  letter: string; // "A+", "B0", "-"
  points: number; // 4.5 scale
  category: string; // "MR-M"
}

/** A letter INS has given: '' and '-' mean the course isn't graded. */
export const isGraded = (r: GradeRecord) => r.letter !== '' && r.letter !== '-';

/**
 * A term's GPA: points weighted by credits, over the letters that carry points
 * (A+ to F). P, S, W and anything else INS may print carry none and are left
 * out, so a term of only those has no GPA. Null then.
 */
export function termGpa(records: GradeRecord[]): number | null {
  const counted = records.filter((r) => /^[A-DF][+0-]?$/.test(r.letter) && r.credits > 0);
  const credits = counted.reduce((sum, r) => sum + r.credits, 0);
  return credits ? counted.reduce((sum, r) => sum + r.points * r.credits, 0) / credits : null;
}

/** INS "View Grades and Standings". Deliberately has no field for the national ID the XML carries. */
export interface GradeReport {
  gpa: number;
  creditsEarned: number;
  yearOfStudy: number;
  records: GradeRecord[];
}

/** A number the way a mark reads best: 37, 0.37, 6.25, never 37.00. */
export const plainNumber = (v: number) => v.toFixed(2).replace(/\.?0+$/, '');

/** One marked thing in an eClass course: a row of its grades page, or of its assignment and quiz lists where that page is closed. */
export interface GradeItem {
  key: string; // the same on every refresh: "m<module id>" or "g<grade item id>"
  name: string;
  category: string; // '' when it sits directly under the course
  mark: string; // as eClass shows it: "8.50", "A"; '-' or '' while unmarked
  grade: number | null; // the mark as a number, when it is one
  max: number | null;
  weight: number | null; // % of its category ("Calculated weight"); null where eClass shows "-"
  categoryWeight: number | null; // the category's % of the course total; 100 directly under the course
  contribution: number | null; // points in the course total, eClass's "백분 환산 점수"
  moduleId: number | null; // for opening it, when it is an activity
  moduleType: string | null; // "assign", "quiz", ...
}

export const isMarked = (i: GradeItem) => i.mark !== '' && i.mark !== '-';

/** "8.5 / 10", or the mark alone when it isn't a number or has no maximum. */
export function itemScore(i: GradeItem): string {
  if (i.grade == null) return i.mark;
  return i.max == null ? plainNumber(i.grade) : `${plainNumber(i.grade)} / ${plainNumber(i.max)}`;
}

/** A category of the grades page and its % of the course total. Listed even with nothing in it yet: a Final exam worth 25% before the final exists. */
export interface GradeCategory {
  name: string;
  weight: number | null;
}

/**
 * Where a course's marks came from. Professors can close the grades page ("Can
 * not view grades"), which leaves the assignment and quiz lists; those have
 * marks but no weights. 'none': neither has anything.
 */
export type GradeSource = 'gradebook' | 'activities' | 'none';

/** One course's marks in eClass. */
export interface CourseGrades {
  course: Course;
  source: GradeSource;
  items: GradeItem[];
  categories: GradeCategory[];
  percent?: number | null; // the course total, %, as eClass works it out
}

/** The mail folders shown, in the sidebar's order, by EWS distinguished folder id. */
export const mailFolders = [
  { id: 'inbox', ews: 'inbox', label: 'Inbox' },
  { id: 'drafts', ews: 'drafts', label: 'Drafts' },
  { id: 'sent', ews: 'sentitems', label: 'Sent' },
  { id: 'deleted', ews: 'deleteditems', label: 'Deleted' },
  { id: 'junk', ews: 'junkemail', label: 'Junk' },
  { id: 'notes', ews: 'notes', label: 'Notes' },
] as const;

export type MailFolder = (typeof mailFolders)[number]['id'];

/** Folders whose rows name who the mail went to rather than who sent it. */
export const outgoingFolder = (f: MailFolder) => f === 'drafts' || f === 'sent';

export interface MailFolderCount {
  unread: number;
  total: number;
}

/** A person or list on a message. */
export interface MailAddress {
  name: string;
  address: string;
}

export const addressLabel = (a: MailAddress) => a.name || a.address;

/** A message header (no body) for a folder list. */
export interface MailHeader {
  id: string;
  from: string;
  to: string; // Exchange's display line of the To recipients
  subject: string;
  preview: string;
  received: number;
  unread: boolean;
  hasAttachments: boolean;
}

/** A file attached to a message: name and size only. */
export interface MailAttachment {
  id: string; // EWS AttachmentId, for downloading it
  name: string;
  size: number; // bytes; 0 when Exchange didn't say
}

/** A file to send with a message. */
export interface OutgoingAttachment {
  name: string;
  contentType: string;
  base64: string;
}

/** One opened message. Fetched when opened, not cached. */
export interface MailMessage {
  id: string;
  changeKey: string; // the version Exchange wants for replies and sending a draft
  from: string; // display name, or the address when there is none
  fromAddress: string;
  subject: string;
  received: number;
  unread: boolean;
  body: string; // plain text, \n line breaks
  attachments: MailAttachment[];
  to: MailAddress[];
  cc: MailAddress[];
  bcc: MailAddress[];
  receivedBy: string; // the student's own address, on mail they received
  isDraft: boolean;
}

export type ComposeKind = 'fresh' | 'reply' | 'replyAll' | 'forward' | 'draft';

/**
 * A message to send or save as a draft. For a reply or forward, ref is the
 * original: Exchange adds "RE:"/"FW:", works out a reply's recipients and
 * quotes the original below body. For 'draft', ref is the saved draft and an
 * undefined field stays as saved.
 */
export interface OutgoingMail {
  kind: ComposeKind;
  ref?: { id: string; changeKey: string };
  to?: string[];
  cc?: string[];
  bcc?: string[];
  subject?: string;
  body?: string;
  /** Files to add. For 'draft', they join what the saved draft already has. */
  attachments?: OutgoingAttachment[];
}
