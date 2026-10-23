package uz.inha.kamol1dn.inha_app.campus

import java.time.LocalDateTime

// The Flutter app's cached data, read on the Android side (lib/models/models.dart).
// Times are local wall-clock times, as the app stores them.

/** One timetable slot from EduPage. [weekday] is 1 (Monday) to 7. */
data class Lesson(
    val weekday: Int,
    val start: String, // "09:00"
    val end: String,
    val subject: String,
    val room: String = "",
    val teacher: String = "",
    val kind: String = "", // "Lecture", "Lab" or ""
)

/** [wire] is the name the Dart enum is stored under. */
enum class DeadlineKind(val wire: String) {
    ASSIGNMENT("assignment"),
    QUIZ("quiz"),
    VOD("vod"),
    OTHER("other"),

    /** eClass's scheduled class period (교시): not something due, never shown as a deadline. */
    CLASS_PERIOD("classPeriod");

    companion object {
        fun of(wire: String): DeadlineKind = entries.first { it.wire == wire }
    }
}

/** An item from eClass's upcoming events. A VOD item is a watch window that closes at [end]. */
data class Deadline(
    val title: String,
    val courseName: String,
    val kind: DeadlineKind,
    val end: LocalDateTime,
    val start: LocalDateTime? = null,
    val moduleId: Int? = null,
    val moduleType: String? = null,
    /** Handed in or attempted, read from the item's own eClass page. */
    val done: Boolean = false,
    val doneAt: LocalDateTime? = null,
)

data class Course(val id: Int, val name: String, val code: String = "", val professor: String = "")

enum class AttendanceMark { PRESENT, ABSENT, LATE, OTHER, UNMARKED }

data class AttendanceEntry(val date: LocalDateTime, val label: String, val mark: AttendanceMark)

data class VodProgress(val week: Int, val title: String, val lengthSec: Int, val percent: Double) {
    val done: Boolean get() = percent >= 100
}

data class CourseAttendance(
    val course: Course,
    val classes: List<AttendanceEntry> = emptyList(),
    val vods: List<VodProgress> = emptyList(),
) {
    fun count(mark: AttendanceMark) = classes.count { it.mark == mark }
}

/** One course result from INS. [letter] is "-" while the course is not graded. */
data class GradeRecord(
    val term: String,
    val termKey: Int,
    val code: String,
    val name: String,
    val credits: Double,
    val letter: String,
    val points: Double,
) {
    val graded: Boolean get() = letter.isNotEmpty() && letter != "-"
}

data class GradeReport(
    val gpa: Double,
    val creditsEarned: Double,
    val yearOfStudy: Int,
    val records: List<GradeRecord>,
)

/** A cached value and when it was fetched. */
data class Cached<T>(val value: T, val at: LocalDateTime)

/** The last time a service answered with the saved login. */
data class AccountCheck(val ok: Boolean, val at: LocalDateTime)
