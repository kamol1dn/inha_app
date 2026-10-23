package uz.inha.kamol1dn.inha_app.appfunctions

import androidx.annotation.RequiresApi
import androidx.appfunctions.AppFunctionDeclaration
import androidx.appfunctions.AppFunctionElementNotFoundException
import androidx.appfunctions.AppFunctionInvalidArgumentException
import androidx.appfunctions.AppFunctionService
import androidx.appfunctions.AppFunctionServiceEntryPoint
import java.time.LocalDate
import java.time.LocalDateTime
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uz.inha.kamol1dn.inha_app.campus.Campus

/**
 * Read-only AppFunctions over the IUT app's cached university data: the timetable (EduPage),
 * deadlines and attendance (eClass) and grades (INS). They read the cache the app keeps on the
 * phone and never go online, sign in or change anything. KSP generates `CampusAppFunctionService`
 * and `assets/campus_app_functions.xml` from this class.
 */
@RequiresApi(36)
@AppFunctionServiceEntryPoint(
    serviceName = "CampusAppFunctionService",
    appFunctionXmlFileName = "campus_app_functions",
)
abstract class BaseCampusAppFunctionService : AppFunctionService() {

    private suspend fun <T> answer(block: CampusFunctions.() -> T): T = withContext(Dispatchers.IO) {
        val functions = CampusFunctions(Campus.read(applicationContext), LocalDateTime.now())
        try {
            functions.block()
        } catch (e: NotAvailable) {
            throw AppFunctionElementNotFoundException(e.message ?: "Not available")
        } catch (e: BadArgument) {
            throw AppFunctionInvalidArgumentException(e.message ?: "Invalid argument")
        }
    }

    /**
     * Get the student's next class from their university timetable: the class in progress now,
     * or else the next one within 7 days, with its room and times.
     *
     * @return The class (null when there is none in the next 7 days) and when the timetable was
     *   last fetched.
     * @throws AppFunctionElementNotFoundException If the timetable hasn't been loaded on this phone.
     *   Suggest the user open the IUT app once.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun getNextClass(): NextClassResult = answer { nextClass() }

    /**
     * Get the student's classes on one day, in time order, with rooms and times.
     *
     * @param day The date to list. Null means today. A weekend day usually has no classes.
     * @return The day's classes (an empty list when there are none) and when the timetable was
     *   last fetched.
     * @throws AppFunctionElementNotFoundException If the timetable hasn't been loaded on this phone.
     *   Suggest the user open the IUT app once.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun getSchedule(day: LocalDate? = null): DaySchedule = answer { schedule(day) }

    /**
     * Get the student's open eClass work: assignments not submitted, quizzes not attempted and
     * lecture videos not fully watched, due within the given number of days, soonest first.
     * Items overdue by less than 24 hours come first. Submitted and watched items are left out.
     *
     * @param withinDays How many days ahead to look, 1 to 120. Defaults to 7.
     * @return The open items and when eClass was last fetched.
     * @throws AppFunctionElementNotFoundException If eClass data isn't on the phone, for example
     *   when the user hasn't signed in to eClass in the IUT app. The message says which.
     * @throws AppFunctionInvalidArgumentException If withinDays is outside 1 to 120.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun getUpcomingDeadlines(withinDays: Int = 7): DeadlinesResult = answer { upcomingDeadlines(withinDays) }

    /**
     * Get the student's class absences per course against the absence limits they set in the
     * IUT app, courses at or near their limit first, with lecture-video progress.
     *
     * @param course Part of a course name to look up one course, for example "multimedia". Null
     *   or empty lists every course.
     * @return The matching courses and when eClass was last fetched.
     * @throws AppFunctionElementNotFoundException If no course matches (the message lists the
     *   course names to choose from), or if eClass data isn't on the phone.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun getAttendance(course: String? = null): AttendanceResult = answer { attendance(course) }

    /**
     * Get the student's grade standing: cumulative GPA on a 4.5 scale, credits earned, year of
     * study, and the final grades of the most recent graded term.
     *
     * @return The summary and when INS was last fetched.
     * @throws AppFunctionElementNotFoundException If grades aren't on the phone, for example when
     *   the user hasn't signed in to INS in the IUT app.
     */
    @AppFunctionDeclaration(isDescribedByKDoc = true)
    suspend fun getGradesSummary(): GradesSummary = answer { gradesSummary() }
}
