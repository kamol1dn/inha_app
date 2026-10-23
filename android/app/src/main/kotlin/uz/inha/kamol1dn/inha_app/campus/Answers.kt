package uz.inha.kamol1dn.inha_app.campus

import java.time.Duration
import java.time.LocalDateTime
import kotlin.math.ceil
import kotlin.math.floor

// What the widgets and AppFunctions answer, built from the rules above. Pure.

/** The class in progress or the next one, and the next open item. */
data class UpNext(
    val slot: ClassSlot?,
    val current: Boolean,
    /** Set when the class's course is in attendance trouble: its warning goes on the class. */
    val trouble: AbsenceState?,
    val due: Deadline?,
)

fun upNext(lessons: List<Lesson>, deadlines: List<Deadline>, att: List<CourseAttendance>, limits: Map<Int, Int>, now: LocalDateTime): UpNext {
    val slot = nextLesson(lessons, now)
    return UpNext(
        slot = slot,
        current = slot?.inProgress(now) == true,
        trouble = slot?.let { troubleFor(it.lesson, att, limits) },
        due = pendingWithin(deadlines, att, now, null).firstOrNull(),
    )
}

/** The attendance state of a lesson's course, when it is in trouble. */
fun troubleFor(l: Lesson, att: List<CourseAttendance>, limits: Map<Int, Int>): AbsenceState? {
    val c = att.firstOrNull { isLessonOf(l, it.course) } ?: return null
    return AbsenceState.of(c, limits).takeIf { it.trouble }
}

sealed interface TodayRow

data class ClassRow(val slot: ClassSlot, val current: Boolean, val trouble: AbsenceState?) : TodayRow

data class DueRow(val deadline: Deadline, val status: Status?, val vod: VodProgress?) : TodayRow

enum class NoteKind { FREE_AFTER, NO_MORE_CLASSES, NO_CLASSES }

data class NoteRow(val kind: NoteKind, val at: LocalDateTime?) : TodayRow

/**
 * The rest of today, as Today's rail has it (lib/data/rail.dart): overdue items, the class in
 * progress, the classes still to come and what is due today, in time order, then a closing note.
 * [next] is the first class after today, for when today has no more.
 */
data class TodayPlan(val overdue: List<DueRow>, val rows: List<TodayRow>, val next: ClassSlot?)

fun todayPlan(
    lessons: List<Lesson>?,
    deadlines: List<Deadline>,
    att: List<CourseAttendance>,
    limits: Map<Int, Int>,
    now: LocalDateTime,
): TodayPlan {
    val today = now.toLocalDate()
    val due = needsAttention(deadlines, att, now)
    fun row(d: Deadline) = DueRow(d, deadlineStatus(d, now), vodFor(d, att))
    val overdue = due.filter { it.end.isBefore(now) }.map(::row)

    val todays = lessonsOn(lessons.orEmpty(), today)
    val warned = mutableSetOf<String>()
    fun classRow(s: ClassSlot): ClassRow {
        val trouble = troubleFor(s.lesson, att, limits)?.takeIf { warned.add(norm(s.lesson.subject)) }
        return ClassRow(s, s.inProgress(now), trouble)
    }

    val timed = mutableListOf<Triple<LocalDateTime, Int, TodayRow>>()
    for (s in todays.filter { it.end.isAfter(now) }) timed += Triple(s.start, 1, classRow(s))
    val tomorrow = today.plusDays(1).atStartOfDay()
    for (d in due.filter { !it.end.isBefore(now) && it.end.isBefore(tomorrow) }) timed += Triple(d.end, 2, row(d))

    var next: ClassSlot? = null
    if (lessons != null) {
        val upcoming = todays.filter { it.end.isAfter(now) }
        when {
            todays.isEmpty() -> timed += Triple(now, 0, NoteRow(NoteKind.NO_CLASSES, null))
            upcoming.isEmpty() -> timed += Triple(now, 0, NoteRow(NoteKind.NO_MORE_CLASSES, null))
            else -> timed += Triple(todays.last().end, 0, NoteRow(NoteKind.FREE_AFTER, todays.last().end))
        }
        if (upcoming.isEmpty()) next = nextLesson(lessons, tomorrow)
    }
    timed.sortWith(compareBy({ it.first }, { it.second }))
    return TodayPlan(overdue, timed.map { it.third }, next)
}

/** A course on the attendance widget: its absences and its next class. */
data class CourseLine(val c: CourseAttendance, val state: AbsenceState, val next: ClassSlot?)

/**
 * Courses in attendance trouble first, then the unwatched VOD windows that close within 72 h,
 * then every other course in timetable order.
 */
data class AttendancePlan(val trouble: List<CourseLine>, val vods: List<DueRow>, val others: List<CourseLine>)

fun attendancePlan(
    att: List<CourseAttendance>,
    deadlines: List<Deadline>,
    lessons: List<Lesson>,
    limits: Map<Int, Int>,
    now: LocalDateTime,
): AttendancePlan {
    val lines = troubleOrder(att, limits, lessons).map { c ->
        CourseLine(c, AbsenceState.of(c, limits), nextLesson(lessons, now) { isLessonOf(it, c.course) })
    }
    val vods = needsAttention(deadlines, att, now)
        .filter { it.kind == DeadlineKind.VOD }
        .map { DueRow(it, deadlineStatus(it, now), vodFor(it, att)) }
    return AttendancePlan(lines.filter { it.state.trouble }, vods, lines.filterNot { it.state.trouble })
}

/**
 * When the widgets next say something different with the clock alone: a class starts or ends,
 * an item turns urgent, overdue or drops off, the day changes, or a countdown moves on (every
 * 5 minutes within an hour of a class and during it, 15 within 3 hours, else 30).
 */
fun nextTick(lessons: List<Lesson>, deadlines: List<Deadline>, att: List<CourseAttendance>, now: LocalDateTime): LocalDateTime {
    val at = mutableListOf(now.toLocalDate().plusDays(1).atStartOfDay())
    for (s in lessonsOn(lessons, now.toLocalDate())) at += listOf(s.start, s.end)
    val next = nextLesson(lessons, now)
    if (next != null) at += listOf(next.start, next.end)
    for (d in deadlines.filter { isPending(it, att, now) }) {
        val e = d.end
        at += if (d.kind == DeadlineKind.VOD) {
            listOf(e.minusHours(72), e.minusHours(12), e)
        } else {
            listOf(e.minusHours(72), e.minusHours(24), e.minusHours(3), e, e.plusHours(24))
        }
    }
    val cadence = when {
        next == null -> 30L
        next.inProgress(now) || Duration.between(now, next.start) <= Duration.ofHours(1) -> 5L
        Duration.between(now, next.start) <= Duration.ofHours(3) -> 15L
        else -> 30L
    }
    at += now.plusMinutes(cadence)
    val soonest = at.filter { it.isAfter(now) }.min()
    return maxOf(soonest, now.plusMinutes(1))
}

/** When each source counts as stale (DESIGN.md 7). */
val timetableStaleAfter: Duration = Duration.ofHours(24)
val eclassStaleAfter: Duration = Duration.ofHours(3)
val insStaleAfter: Duration = Duration.ofHours(24)

/** "as of Tue 18:04" once [cached] is older than [after], else null. */
fun asOf(cached: Cached<*>?, now: LocalDateTime, after: Duration): String? {
    val at = cached?.at ?: return null
    return if (Duration.between(at, now) > after) "as of ${Fmt.updatedAt(at, now)}" else null
}

/** "Timetable as of Tue 18:04" once [cached] is older than [after], else null. */
fun staleNote(source: String, cached: Cached<*>?, now: LocalDateTime, after: Duration): String? =
    asOf(cached, now, after)?.let { "$source $it" }

/** What to say when there is no eClass data at all. */
fun eclassMissing(account: AccountCheck?, what: String): String =
    if (account?.ok == true) "Open the app to load $what from eClass." else "Sign in to eClass in the app to see $what."

/** The app's wording for rows (lib/features/rail_rows.dart, courses_screen.dart). */
object Words {
    /** "Not submitted", "Not attempted", "Closes · 62% watched": what is left to do. */
    fun dueState(d: Deadline, vod: VodProgress?) = when (d.kind) {
        DeadlineKind.ASSIGNMENT -> "Not submitted"
        DeadlineKind.QUIZ -> "Not attempted"
        DeadlineKind.VOD -> if (vod == null) "Closes" else "Closes · ${floor(vod.percent).toInt()}% watched"
        else -> ""
    }

    /** "Due in 5 h · not submitted", "Overdue 2 h · not attempted", "62% watched, 21 min left". */
    fun dueWarning(d: Deadline, vod: VodProgress?, now: LocalDateTime): String {
        if (d.kind == DeadlineKind.VOD) {
            if (vod == null) return "Closes ${Fmt.relative(d.end, now)} · no watch progress yet"
            val left = ceil((vod.lengthSec / 60) * (100 - vod.percent) / 100).toInt()
            return if (vod.percent < 1) "Not started, $left min" else "${floor(vod.percent).toInt()}% watched, $left min left"
        }
        val rel = Fmt.relative(d.end, now)
        val whenText = if (d.end.isBefore(now)) rel else "Due $rel"
        val state = when (d.kind) {
            DeadlineKind.ASSIGNMENT -> "not submitted"
            DeadlineKind.QUIZ -> "not attempted"
            else -> ""
        }
        return if (state.isEmpty()) whenText else "$whenText · $state"
    }

    /**
     * When it is due and what is left, for a place with no time column: "Due Sat 23:59 · not
     * attempted", "Closes Sun 23:59 · 62% watched".
     */
    fun dueWhen(d: Deadline, vod: VodProgress?, now: LocalDateTime): String {
        if (d.kind != DeadlineKind.VOD) return dueWarning(d, vod, now)
        val closes = "Closes ${Fmt.relative(d.end, now)}"
        return if (vod == null) closes else "$closes · ${floor(vod.percent).toInt()}% watched"
    }

    /** The line under a due item's title: a warning when urgent, otherwise state and course. */
    fun dueLine(row: DueRow, now: LocalDateTime): String =
        if (row.status != null) dueWarning(row.deadline, row.vod, now)
        else listOf(dueState(row.deadline, row.vod), courseName(row.deadline.courseName)).filter { it.isNotEmpty() }.joinToString(" · ")

    /** "today 14:00", "tomorrow 13:00", "Mon 13:00". */
    fun classWhen(s: ClassSlot, now: LocalDateTime): String = when (val h = Fmt.dayHeader(s.start, now)) {
        "Today", "Tomorrow" -> "${h.lowercase()} ${s.lesson.start}"
        else -> "${Fmt.weekdayShort(s.day.dayOfWeek.value)} ${s.lesson.start}"
    }

    fun capitalized(s: String) = if (s.isEmpty()) s else s[0].uppercase() + s.substring(1)

    /** "B202 · Lecture" */
    fun lessonMeta(l: Lesson) = listOf(l.room, l.kind).filter { it.isNotEmpty() }.joinToString(" · ")

    /** "6 of 8 absences used · 2 left" */
    fun absenceWarning(a: AbsenceState): String {
        val left = a.left ?: return a.line
        if (left > 0) return "${a.line} · $left left"
        if (left == 0) return "${a.line} · none left"
        return "${a.line} · over by ${-left}"
    }

    /** A course row's second line: "2 left · next Mon 13:00" in trouble, else the next class. */
    fun courseLine(line: CourseLine, now: LocalDateTime): String {
        val whenText = line.next?.let { classWhen(it, now) }
        val a = line.state
        if (a.status != null) {
            val left = a.left!!
            val head = when {
                left > 0 -> "$left left"
                left == 0 -> "At the limit"
                else -> "Over by ${-left}"
            }
            return listOfNotNull(head, whenText?.let { "next $it" }).joinToString(" · ")
        }
        if (line.c.classes.isEmpty()) return "No class attendance in eClass"
        val next = line.next?.let { n ->
            listOf(if (whenText!!.startsWith("to")) capitalized(whenText) else "Next $whenText", n.lesson.room)
                .filter { it.isNotEmpty() }.joinToString(" · ")
        }
        return listOfNotNull(if (a.limit == null) "Limit not set" else null, next).joinToString(" · ")
    }

    /** "VOD 10 of 12 watched", or null for a course without VODs. */
    fun vodLine(c: CourseAttendance): String? {
        if (c.vods.isEmpty()) return null
        val unwatched = c.vods.count { !it.done }
        return if (unwatched == 0) "VOD all ${c.vods.size} watched" else "VOD ${c.vods.size - unwatched} of ${c.vods.size} watched"
    }

    /** "Now · until 15:30 · 40 min left" or "Next · in 40 min". */
    fun classLabel(s: ClassSlot, now: LocalDateTime): String =
        if (s.inProgress(now)) "Now · until ${s.lesson.end} · ${Fmt.duration(Duration.between(now, s.end))} left"
        else if (s.day == now.toLocalDate()) "Next · ${Fmt.relative(s.start, now)}"
        else "Next · ${Fmt.dayHeader(s.start, now)} ${s.lesson.start}"
}
