package uz.inha.kamol1dn.inha_app.appfunctions

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import uz.inha.kamol1dn.inha_app.campus.Campus
import uz.inha.kamol1dn.inha_app.campus.at
import uz.inha.kamol1dn.inha_app.campus.campus
import uz.inha.kamol1dn.inha_app.campus.fri
import uz.inha.kamol1dn.inha_app.campus.tashkent

class CampusFunctionsTest {
    private val f = CampusFunctions(campus(), fri)

    @Test
    fun nextClass() {
        val r = f.nextClass()
        val c = r.nextClass!!
        assertEquals("Embedded Software & Design", c.course)
        assertEquals("B202", c.room)
        assertEquals(at(23, 14), c.start)
        assertEquals(at(23, 15, 30), c.end)
        assertFalse(c.inProgress)
        assertEquals("", c.attendanceWarning)
        assertEquals(at(23, 8, 41).plusNanos(123_456_000), r.timetableAsOf)
    }

    @Test
    fun nextClassCarriesTheAttendanceWarning() {
        val c = CampusFunctions(campus(), at(23, 15, 45)).nextClass().nextClass!!
        assertEquals("Artificial Intelligence", c.course)
        assertEquals("6 of 8 absences used · 2 left", c.attendanceWarning)
    }

    @Test
    fun noClassWithinAWeek() {
        val empty = campus("cache.lessons" to """{"at":"2026-10-23T08:41:00.000","value":[]}""")
        assertNull(CampusFunctions(empty, fri).nextClass().nextClass)
    }

    @Test
    fun scheduleForADay() {
        val today = f.schedule(null)
        assertEquals(LocalDate.of(2026, 10, 23), today.date)
        assertEquals(listOf("09:00", "14:00", "16:00"), today.classes.map { "%02d:%02d".format(it.start.hour, it.start.minute) })
        assertTrue(f.schedule(LocalDate.of(2026, 10, 24)).classes.isEmpty())
        assertEquals(listOf("Multimedia Computing", "Artificial Intelligence"), f.schedule(LocalDate.of(2026, 10, 26)).classes.map { it.course })
    }

    @Test
    fun deadlinesAreOpenWorkOnlyWithNamesNotCodes() {
        val r = f.upcomingDeadlines(7)
        assertEquals(listOf("Assignment 1", "Quiz 2 Week 6 - 2%", "Week 7"), r.items.map { it.title })
        val quiz = r.items[1]
        assertEquals("Artificial Intelligence", quiz.course)
        assertEquals("quiz", quiz.kind)
        assertEquals("Not attempted", quiz.state)
        assertEquals("normal", quiz.urgency)
        assertEquals("warning", r.items[0].urgency)
        assertEquals("62% watched", r.items[2].state)
        assertEquals(at(23, 12), r.eclassAsOf)
        assertEquals(4, f.upcomingDeadlines(30).items.size)
    }

    @Test
    fun overdueWorkComesFirst() {
        val r = CampusFunctions(campus(), at(24, 9)).upcomingDeadlines(7)
        assertTrue(r.items.first().overdue)
        assertEquals("danger", r.items.first().urgency)
    }

    @Test
    fun withinDaysIsChecked() {
        assertThrows(BadArgument::class.java) { f.upcomingDeadlines(0) }
        assertThrows(BadArgument::class.java) { f.upcomingDeadlines(121) }
    }

    @Test
    fun attendanceTroubleFirstAndNoGuessedLimits() {
        val r = f.attendance(null)
        assertEquals(
            listOf("Artificial Intelligence", "Multimedia Computing", "Embedded Software & Design", "Distinguished Lecture in Social Science and Art"),
            r.courses.map { it.course },
        )
        val ai = r.courses[0]
        assertEquals(6, ai.absences)
        assertEquals(8, ai.limit)
        assertEquals(2, ai.left)
        assertEquals("warning", ai.status)
        assertEquals(at(23, 16), ai.nextClass)
        val mm = r.courses[1]
        assertEquals(1, mm.lates)
        assertEquals("ok", mm.status)
        val esd = r.courses[2]
        assertNull(esd.limit)
        assertNull(esd.left)
        assertEquals("limit not set", esd.status)
        val dl = r.courses[3]
        assertEquals("no attendance record", dl.status)
        assertEquals(1, dl.videosWatched)
        assertEquals(2, dl.videosTotal)
    }

    @Test
    fun attendanceForOneCourse() {
        assertEquals(listOf("Multimedia Computing"), f.attendance("multimedia").courses.map { it.course })
        val e = assertThrows(NotAvailable::class.java) { f.attendance("calculus") }
        assertTrue(e.message!!.contains("Artificial Intelligence, Multimedia Computing"))
    }

    @Test
    fun gradesSummary() {
        val g = f.gradesSummary()
        assertEquals(3.87, g.gpa, 0.0)
        assertEquals(4.5, g.gpaScale, 0.0)
        assertEquals(98.0, g.creditsEarned, 0.0)
        assertEquals("2026 Spring Semester", g.latestGradedTerm)
        assertEquals(listOf("Computer Networks" to "A+", "Operating Systems" to "B+"), g.latestTermGrades.map { it.course to it.letter })
        assertEquals(listOf("Multimedia Computing"), g.coursesNotGradedYet)
    }

    @Test
    fun missingDataSaysWhatToDo() {
        val nothing = CampusFunctions(Campus.from({ null }, tashkent), fri)
        assertTrue(assertThrows(NotAvailable::class.java) { nothing.nextClass() }.message!!.contains("open the IUT app"))
        assertTrue(assertThrows(NotAvailable::class.java) { nothing.upcomingDeadlines(7) }.message!!.contains("sign in"))
        assertTrue(assertThrows(NotAvailable::class.java) { nothing.attendance(null) }.message!!.contains("eClass"))
        assertTrue(assertThrows(NotAvailable::class.java) { nothing.gradesSummary() }.message!!.contains("INS"))
        val signedIn = campus("cache.deadlines" to null)
        assertTrue(
            assertThrows(NotAvailable::class.java) { CampusFunctions(signedIn, fri).upcomingDeadlines(7) }.message!!
                .contains("hasn't been loaded"),
        )
    }
}
