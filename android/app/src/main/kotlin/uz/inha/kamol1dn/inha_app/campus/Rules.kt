package uz.inha.kamol1dn.inha_app.campus

import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime

// The rules the app already uses, so the widgets and AppFunctions never disagree with it:
// lib/data/urgency.dart, lib/data/absence.dart and the timetable part of lib/data/rail.dart.
// Pure: data and a clock in, answers out.

enum class Status { OK, WARNING, DANGER, INFO }

/** How far ahead Today looks for deadlines and VOD windows (DESIGN.md 7). */
val todayWindow: Duration = Duration.ofHours(72)

/** Kinds that are something due. Class periods are scheduled classes, never deadlines. */
fun isDue(d: Deadline) = d.kind != DeadlineKind.CLASS_PERIOD

/** The course's attendance record for a calendar event. Names can be cut short on either side. */
fun courseFor(courseName: String, all: List<CourseAttendance>): CourseAttendance? {
    val n = norm(courseName)
    if (n.isEmpty()) return null
    return all.firstOrNull {
        val m = norm(it.course.name)
        m == n || m.startsWith(n) || n.startsWith(m)
    }
}

/** The progress row for a VOD-window event, or null if unknown. */
fun vodFor(d: Deadline, all: List<CourseAttendance>): VodProgress? {
    if (d.kind != DeadlineKind.VOD) return null
    val course = courseFor(d.courseName, all) ?: return null
    val t = norm(d.title)
    return course.vods.firstOrNull { norm(it.title) == t }
}

fun vodWatched(d: Deadline, all: List<CourseAttendance>): Boolean? = vodFor(d, all)?.done

/** Nothing left to do: handed in, attempted, or (a VOD) fully watched. */
fun isDone(d: Deadline, att: List<CourseAttendance>) = d.done || vodWatched(d, att) == true

/** Null means plain; otherwise the status the guide assigns. */
fun deadlineStatus(d: Deadline, now: LocalDateTime): Status? {
    val left = Duration.between(now, d.end)
    if (d.kind == DeadlineKind.VOD) {
        if (left.toHours() < 12) return Status.DANGER
        if (left.toHours() < 72) return Status.WARNING
        return null
    }
    if (left.isNegative || left.toHours() < 3) return Status.DANGER
    if (left.toHours() < 24) return Status.WARNING
    return null
}

/**
 * Still open: due, not done, and not past. Overdue work stays for 24 h; a VOD window that has
 * closed is gone (the absence is recorded instead).
 */
fun isPending(d: Deadline, att: List<CourseAttendance>, now: LocalDateTime): Boolean {
    if (!isDue(d) || isDone(d, att)) return false
    val left = Duration.between(now, d.end)
    return if (d.kind == DeadlineKind.VOD) !left.isNegative else left > Duration.ofHours(-24)
}

/** Today's "needs attention": open items due within 72 h, overdue ones first. Never class periods. */
fun needsAttention(all: List<Deadline>, att: List<CourseAttendance>, now: LocalDateTime): List<Deadline> =
    all.filter { isPending(it, att, now) && Duration.between(now, it.end) <= todayWindow }.sortedBy { it.end }

/** Open items, soonest first, up to [within] ahead (overdue ones first). */
fun pendingWithin(all: List<Deadline>, att: List<CourseAttendance>, now: LocalDateTime, within: Duration?): List<Deadline> =
    all.filter { isPending(it, att, now) && (within == null || Duration.between(now, it.end) <= within) }.sortedBy { it.end }

// ---------------------------------------------------------------------------
// Timetable
// ---------------------------------------------------------------------------

fun minutes(hhmm: String): Int {
    val p = hhmm.split(':')
    return (p[0].trim().toIntOrNull() ?: 0) * 60 + (p.getOrNull(1)?.trim()?.toIntOrNull() ?: 0)
}

/** A lesson on a date. */
data class ClassSlot(val lesson: Lesson, val day: LocalDate) {
    val start: LocalDateTime get() = day.atStartOfDay().plusMinutes(minutes(lesson.start).toLong())
    val end: LocalDateTime get() = day.atStartOfDay().plusMinutes(minutes(lesson.end).toLong())
    fun inProgress(now: LocalDateTime) = !start.isAfter(now) && end.isAfter(now)
}

/** The classes on [day]; none on the days in [off] (an exam week, `Campus.classFree`). */
fun lessonsOn(lessons: List<Lesson>, day: LocalDate, off: Set<LocalDate> = emptySet()): List<ClassSlot> =
    if (day in off) emptyList()
    else lessons.filter { it.weekday == day.dayOfWeek.value }.sortedBy { minutes(it.start) }.map { ClassSlot(it, day) }

/**
 * The next class [test] accepts: one in progress or still to come today, then the next 7 days,
 * skipping the days in [off].
 */
fun nextLesson(
    lessons: List<Lesson>,
    now: LocalDateTime,
    off: Set<LocalDate> = emptySet(),
    test: (Lesson) -> Boolean = { true },
): ClassSlot? {
    for (i in 0L..7L) {
        val day = now.toLocalDate().plusDays(i)
        lessonsOn(lessons, day, off).firstOrNull { test(it.lesson) && it.end.isAfter(now) }?.let { return it }
    }
    return null
}

/** Whether a timetable subject is this eClass course. */
fun isLessonOf(l: Lesson, course: Course) = courseFor(l.subject, listOf(CourseAttendance(course))) != null

// ---------------------------------------------------------------------------
// Absences
// ---------------------------------------------------------------------------

/** A course's absences against the limit the student set. No limit is ever guessed. */
data class AbsenceState(val used: Int, val limit: Int?) {
    val left: Int? get() = limit?.let { it - used }

    /** Warning once at most max(1, 25% of the allowance) is left; danger at 0 left or over. */
    val status: Status?
        get() {
            val l = left ?: return null
            if (l <= 0) return Status.DANGER
            if (l <= maxOf(1.0, limit!! * 0.25)) return Status.WARNING
            return null
        }

    val trouble: Boolean get() = status != null

    /** "1 left", "At limit", "Over limit"; null when not in trouble. */
    val tag: String?
        get() {
            val l = left ?: return null
            if (status == null) return null
            if (l < 0) return "Over limit"
            if (l == 0) return "At limit"
            return "$l left"
        }

    /** "3 of 4 absences used", "5 absences · limit 4", or the raw count with "limit not set". */
    val line: String
        get() {
            val noun = if (used == 1) "absence" else "absences"
            val lim = limit ?: return "$used $noun · limit not set"
            if (used > lim) return "$used absences · limit $lim"
            return "$used of $lim $noun used"
        }

    /** "6 of 8", or "6" without a limit. */
    val count: String get() = limit?.let { "$used of $it" } ?: "$used"

    companion object {
        fun of(c: CourseAttendance, limits: Map<Int, Int>) = AbsenceState(c.count(AttendanceMark.ABSENT), limits[c.course.id])
    }
}

/** Danger, then warning, then the rest in timetable order; courses not in the timetable last. */
fun troubleOrder(courses: List<CourseAttendance>, limits: Map<Int, Int>, lessons: List<Lesson>): List<CourseAttendance> {
    fun rank(c: CourseAttendance) = when (AbsenceState.of(c, limits).status) {
        Status.DANGER -> 0
        Status.WARNING -> 1
        else -> 2
    }

    fun firstClass(c: CourseAttendance): Int {
        val name = norm(c.course.name)
        var best = 1 shl 30
        for (l in lessons) {
            val subject = norm(l.subject)
            if (subject.isEmpty() || !(subject == name || subject.startsWith(name) || name.startsWith(subject))) continue
            best = minOf(best, l.weekday * 24 * 60 + minutes(l.start))
        }
        return best
    }
    return courses.sortedWith(compareBy<CourseAttendance>({ rank(it) }, { firstClass(it) }, { it.course.name }))
}
