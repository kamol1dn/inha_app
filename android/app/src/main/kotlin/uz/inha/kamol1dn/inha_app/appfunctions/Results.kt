package uz.inha.kamol1dn.inha_app.appfunctions

import androidx.appfunctions.AppFunctionSerializable
import java.time.LocalDate
import java.time.LocalDateTime

// What the AppFunctions return. Gemini may process these on Google's servers, so they carry only
// what answers the question: no mail, no credentials, no student name or ID, no course codes.
// KSP reads each property's own KDoc into the schema the agent sees.

/** A class (lecture or lab) on the student's university timetable. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class ClassInfo(
    /** The course name, for example "Multimedia Computing". */
    val course: String,
    /** The room, for example "B-305". Empty when the timetable has no room for this class. */
    val room: String,
    /** When the class starts, in the phone's local time. */
    val start: LocalDateTime,
    /** When the class ends, in the phone's local time. */
    val end: LocalDateTime,
    /** "Lecture", "Lab", or empty when the timetable doesn't say. */
    val kind: String,
    /** The teacher as the public timetable lists them. Empty when unknown. */
    val teacher: String,
    /** True while the class is in progress. */
    val inProgress: Boolean,
    /** The student's attendance warning for this course, for example "6 of 8 absences used · 2 left". Empty when the course is within its absence limit. */
    val attendanceWarning: String,
)

/** The next class, or none within a week. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class NextClassResult(
    /** The class in progress or the next one within 7 days; null when there is none in that time. */
    val nextClass: ClassInfo?,
    /** When the app last fetched the timetable, in the phone's local time. */
    val timetableAsOf: LocalDateTime,
)

/** One day of the timetable. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class DaySchedule(
    /** The day these classes are on. */
    val date: LocalDate,
    /** The day's classes in time order. Empty when there are no classes that day. */
    val classes: List<ClassInfo>,
    /** When the app last fetched the timetable, in the phone's local time. */
    val timetableAsOf: LocalDateTime,
)

/** Something due on eClass, the university's course site. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class DeadlineInfo(
    /** The item's title, for example "Quiz 2 Week 6 - 2%". */
    val title: String,
    /** The course it belongs to. */
    val course: String,
    /** "assignment", "quiz", "vod" (a lecture video that must be watched before its window closes; missing one counts as an absence) or "other". */
    val kind: String,
    /** When it is due, or when the video's watch window closes, in the phone's local time. */
    val due: LocalDateTime,
    /** True when the due time has passed and it is still not done. Overdue items are listed for 24 hours. */
    val overdue: Boolean,
    /** "danger" (under 3 hours left or overdue; for a video, under 12 hours), "warning" (under 24 hours; for a video, under 72 hours) or "normal". */
    val urgency: String,
    /** What is left to do, for example "Not submitted", "Not attempted" or "62% watched". */
    val state: String,
)

/** Open eClass items, soonest first. Submitted work and fully watched videos are left out. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class DeadlinesResult(
    /** The open items, overdue ones first, then by due time. */
    val items: List<DeadlineInfo>,
    /** When the app last fetched eClass, in the phone's local time. */
    val eclassAsOf: LocalDateTime,
)

/** A course's class attendance against the absence limit the student set in the app. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class CourseAttendanceInfo(
    /** The course name. */
    val course: String,
    /** Absences recorded so far this semester. */
    val absences: Int,
    /** Late marks recorded so far. */
    val lates: Int,
    /** The most absences allowed, as the student set it in the app. Null when not set; it is never guessed. */
    val limit: Int?,
    /** Absences still allowed before reaching the limit. Negative when over it. Null without a limit. */
    val left: Int?,
    /** "over limit", "at limit", "warning" (at most a quarter of the allowance left), "ok", "limit not set", or "no attendance record" (the course takes no class attendance in eClass). */
    val status: String,
    /** Lecture videos fully watched. */
    val videosWatched: Int,
    /** Lecture videos the course tracks. 0 when it tracks none. */
    val videosTotal: Int,
    /** The course's next class on the timetable within 7 days; null when none. */
    val nextClass: LocalDateTime?,
)

/** Attendance for one or all courses, courses in trouble first. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class AttendanceResult(
    /** The courses, those at or near their absence limit first. */
    val courses: List<CourseAttendanceInfo>,
    /** When the app last fetched eClass, in the phone's local time. */
    val eclassAsOf: LocalDateTime,
)

/** One course's final grade. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class GradeInfo(
    /** The course name. */
    val course: String,
    /** Credits the course is worth. */
    val credits: Double,
    /** The letter grade, for example "A+" or "B0" (Inha's scale has A+, A0, B+, B0, C+, C0, D+, D0, F). */
    val letter: String,
)

/** The student's grade standing from INS, the university's records system. */
@AppFunctionSerializable(isDescribedByKDoc = true)
data class GradesSummary(
    /** Cumulative GPA on a 4.5 scale. */
    val gpa: Double,
    /** The top of the GPA scale: 4.5. */
    val gpaScale: Double,
    /** Credits earned so far. */
    val creditsEarned: Double,
    /** The student's year of study. */
    val yearOfStudy: Int,
    /** The most recent term with final grades, for example "2026 Spring Semester". Empty when nothing is graded yet. */
    val latestGradedTerm: String,
    /** The final grades of that term. */
    val latestTermGrades: List<GradeInfo>,
    /** Courses on record that are not graded yet (the current term). */
    val coursesNotGradedYet: List<String>,
    /** When the app last fetched INS, in the phone's local time. */
    val insAsOf: LocalDateTime,
)
