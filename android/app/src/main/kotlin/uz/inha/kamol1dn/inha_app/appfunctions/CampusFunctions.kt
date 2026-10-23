package uz.inha.kamol1dn.inha_app.appfunctions

import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.math.floor
import uz.inha.kamol1dn.inha_app.campus.AbsenceState
import uz.inha.kamol1dn.inha_app.campus.AttendanceMark
import uz.inha.kamol1dn.inha_app.campus.Campus
import uz.inha.kamol1dn.inha_app.campus.ClassSlot
import uz.inha.kamol1dn.inha_app.campus.CourseAttendance
import uz.inha.kamol1dn.inha_app.campus.DeadlineKind
import uz.inha.kamol1dn.inha_app.campus.Fmt
import uz.inha.kamol1dn.inha_app.campus.Lesson
import uz.inha.kamol1dn.inha_app.campus.Status
import uz.inha.kamol1dn.inha_app.campus.Words
import uz.inha.kamol1dn.inha_app.campus.courseName
import uz.inha.kamol1dn.inha_app.campus.deadlineStatus
import uz.inha.kamol1dn.inha_app.campus.isLessonOf
import uz.inha.kamol1dn.inha_app.campus.lessonsOn
import uz.inha.kamol1dn.inha_app.campus.nextLesson
import uz.inha.kamol1dn.inha_app.campus.norm
import uz.inha.kamol1dn.inha_app.campus.pendingWithin
import uz.inha.kamol1dn.inha_app.campus.troubleFor
import uz.inha.kamol1dn.inha_app.campus.troubleOrder
import uz.inha.kamol1dn.inha_app.campus.vodFor

/** The data the question needs isn't on the phone. The message says what the user can do. */
class NotAvailable(message: String) : Exception(message)

/** An argument out of range. */
class BadArgument(message: String) : Exception(message)

/**
 * The answers behind the AppFunctions, from the app's cache. Pure, so they are unit-tested; the
 * service maps [NotAvailable] and [BadArgument] to AppFunction exceptions.
 */
class CampusFunctions(private val c: Campus, private val now: LocalDateTime) {

    private fun timetable() = c.lessons
        ?: throw NotAvailable("The timetable hasn't been loaded yet. Ask the user to open the IUT app once with a connection.")

    private fun eclassMissing(): Nothing = throw NotAvailable(
        if (c.eclassAccount?.ok == true) {
            "eClass data hasn't been loaded yet. Ask the user to open the IUT app once with a connection."
        } else {
            "The user isn't signed in to eClass. Ask them to sign in in the IUT app's Settings."
        },
    )

    private fun classInfo(s: ClassSlot): ClassInfo {
        val l = s.lesson
        val trouble = troubleFor(l, c.attendance?.value.orEmpty(), c.limits)
        return ClassInfo(
            course = l.subject,
            room = l.room,
            start = s.start,
            end = s.end,
            kind = l.kind,
            teacher = l.teacher,
            inProgress = s.inProgress(now),
            attendanceWarning = trouble?.let(Words::absenceWarning) ?: "",
        )
    }

    fun nextClass(): NextClassResult {
        val t = timetable()
        return NextClassResult(nextLesson(t.value, now)?.let(::classInfo), t.at)
    }

    fun schedule(day: LocalDate?): DaySchedule {
        val t = timetable()
        val date = day ?: now.toLocalDate()
        return DaySchedule(date, lessonsOn(t.value, date).map(::classInfo), t.at)
    }

    fun upcomingDeadlines(withinDays: Int): DeadlinesResult {
        if (withinDays !in 1..120) throw BadArgument("withinDays must be between 1 and 120; got $withinDays.")
        val d = c.deadlines ?: eclassMissing()
        val att = c.attendance?.value.orEmpty()
        val items = pendingWithin(d.value, att, now, Duration.ofDays(withinDays.toLong())).map {
            val vod = vodFor(it, att)
            DeadlineInfo(
                title = Fmt.rowTitle(it.title),
                course = courseName(it.courseName),
                kind = it.kind.wire,
                due = it.end,
                overdue = it.end.isBefore(now),
                urgency = urgency(deadlineStatus(it, now)),
                state = when (it.kind) {
                    DeadlineKind.ASSIGNMENT -> "Not submitted"
                    DeadlineKind.QUIZ -> "Not attempted"
                    DeadlineKind.VOD -> vod?.let { v -> "${floor(v.percent).toInt()}% watched" } ?: "No watch progress yet"
                    else -> "Open"
                },
            )
        }
        return DeadlinesResult(items, d.at)
    }

    fun attendance(course: String?): AttendanceResult {
        val a = c.attendance ?: eclassMissing()
        val lessons = c.lessons?.value.orEmpty()
        var courses = troubleOrder(a.value, c.limits, lessons)
        if (!course.isNullOrBlank()) {
            val q = norm(course)
            courses = courses.filter { norm(it.course.name).contains(q) || q.contains(norm(it.course.name)) }
            if (courses.isEmpty()) {
                throw NotAvailable(
                    "No course matches \"$course\". The courses are: ${a.value.joinToString(", ") { it.course.name }}.",
                )
            }
        }
        return AttendanceResult(courses.map { attendanceInfo(it, lessons) }, a.at)
    }

    private fun attendanceInfo(ca: CourseAttendance, lessons: List<Lesson>): CourseAttendanceInfo {
        val s = AbsenceState.of(ca, c.limits)
        val status = when {
            ca.classes.isEmpty() -> "no attendance record"
            s.limit == null -> "limit not set"
            s.left!! < 0 -> "over limit"
            s.left == 0 -> "at limit"
            s.status == Status.WARNING -> "warning"
            else -> "ok"
        }
        return CourseAttendanceInfo(
            course = ca.course.name,
            absences = s.used,
            lates = ca.count(AttendanceMark.LATE),
            limit = s.limit,
            left = s.left,
            status = status,
            videosWatched = ca.vods.count { it.done },
            videosTotal = ca.vods.size,
            nextClass = nextLesson(lessons, now) { isLessonOf(it, ca.course) }?.start,
        )
    }

    fun gradesSummary(): GradesSummary {
        val g = c.grades ?: throw NotAvailable(
            if (c.insAccount?.ok == true) {
                "Grades haven't been loaded yet. Ask the user to open the IUT app once with a connection."
            } else {
                "The user isn't signed in to INS. Ask them to sign in in the IUT app's Settings."
            },
        )
        val r = g.value
        val graded = r.records.filter { it.graded }
        val latest = graded.maxOfOrNull { it.termKey }
        val term = graded.filter { it.termKey == latest }
        return GradesSummary(
            gpa = r.gpa,
            gpaScale = 4.5,
            creditsEarned = r.creditsEarned,
            yearOfStudy = r.yearOfStudy,
            latestGradedTerm = term.firstOrNull()?.term ?: "",
            latestTermGrades = term.map { GradeInfo(it.name, it.credits, it.letter) },
            coursesNotGradedYet = r.records.filter { !it.graded }.map { it.name },
            insAsOf = g.at,
        )
    }

    private fun urgency(s: Status?) = when (s) {
        Status.DANGER -> "danger"
        Status.WARNING -> "warning"
        else -> "normal"
    }
}
