package uz.inha.kamol1dn.inha_app.campus

import java.time.LocalDate
import java.time.LocalDateTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RulesTest {
    private val c = campus()
    private val lessons = c.lessons!!.value
    private val deadlines = c.deadlines!!.value
    private val att = c.attendance!!.value

    private fun titled(t: String) = deadlines.first { it.title == t }

    @Test
    fun classPeriodsAreNeverDue() {
        val period = deadlines.first { it.kind == DeadlineKind.CLASS_PERIOD }
        assertFalse(isDue(period))
        assertFalse(isPending(period, att, at(23, 9)))
        assertTrue(pendingWithin(deadlines, att, at(23, 9), null).none { it.kind == DeadlineKind.CLASS_PERIOD })
    }

    @Test
    fun doneItemsAreHidden() {
        assertFalse(isPending(titled("Lab 4"), att, fri))
        // Week 6 is fully watched, Week 7 is not.
        assertEquals(true, vodWatched(titled("Week 6"), att))
        assertFalse(isPending(titled("Week 6"), att, fri))
        assertTrue(isPending(titled("Week 7"), att, fri))
    }

    @Test
    fun needsAttentionLooks72HoursAhead() {
        assertEquals(
            listOf("Assignment 1", "[QUIZ] 2 Week 6 - 2% (Quiz closes)", "Week 7"),
            needsAttention(deadlines, att, fri).map { it.title },
        )
        assertEquals(4, pendingWithin(deadlines, att, fri, null).size)
    }

    @Test
    fun overdueStaysForADayThenGoes() {
        val a1 = titled("Assignment 1")
        assertTrue(isPending(a1, att, at(24, 9)))
        assertEquals(Status.DANGER, deadlineStatus(a1, at(24, 9)))
        assertFalse(isPending(a1, att, at(25, 0)))
        // A VOD window that has closed is gone at once.
        assertFalse(isPending(titled("Week 7"), att, at(26, 0)))
    }

    @Test
    fun deadlineStatusThresholds() {
        val a1 = titled("Assignment 1") // Fri 23:55
        assertNull(deadlineStatus(a1, at(22, 22)))
        assertEquals(Status.WARNING, deadlineStatus(a1, at(23, 13)))
        assertEquals(Status.DANGER, deadlineStatus(a1, at(23, 21)))
        val vod = titled("Week 7") // Sun 23:59
        assertNull(deadlineStatus(vod, at(22, 12)))
        assertEquals(Status.WARNING, deadlineStatus(vod, fri))
        assertEquals(Status.DANGER, deadlineStatus(vod, at(25, 13)))
    }

    @Test
    fun courseNamesMatchByPrefixEitherWay() {
        assertEquals(2622, courseFor("Artificial Intelligence[202602-AIE3010-001]", att)?.course?.id)
        assertEquals(2592, courseFor("Distinguished Lecture in Social", att)?.course?.id)
        assertNull(courseFor("", att))
        assertNull(courseFor("Calculus", att))
    }

    @Test
    fun nextLessonFindsTodayThenTheWeek() {
        assertEquals("Embedded Software & Design", nextLesson(lessons, fri)!!.lesson.subject)
        val inProgress = nextLesson(lessons, at(23, 14, 30))!!
        assertTrue(inProgress.inProgress(at(23, 14, 30)))
        val monday = nextLesson(lessons, at(23, 18))!!
        assertEquals(at(26, 9), monday.start)
        assertEquals("Multimedia Computing", monday.lesson.subject)
        assertNull(nextLesson(emptyList(), fri))
    }

    @Test
    fun noClassesOnTheExamWeeksDays() {
        val week = (26..30).map { LocalDate.of(2026, 10, it) }.toSet()
        assertTrue(lessonsOn(lessons, LocalDate.of(2026, 10, 26), week).isEmpty())
        assertEquals(2, lessonsOn(lessons, LocalDate.of(2026, 10, 26)).size)
        // Friday evening the week it looks through is the exam week; from its last day, Mon 2 Nov.
        assertNull(nextLesson(lessons, at(23, 18), week))
        assertEquals(LocalDateTime.of(2026, 11, 2, 9, 0), nextLesson(lessons, at(30, 12), week)!!.start)
    }

    @Test
    fun absenceStatusFollowsTheGuide() {
        assertNull(AbsenceState(5, 8).status) // 3 left of 8: fine
        assertEquals(Status.WARNING, AbsenceState(6, 8).status) // 2 left = 25%
        assertEquals(Status.WARNING, AbsenceState(3, 4).status) // 1 left: max(1, 25%)
        assertEquals(Status.DANGER, AbsenceState(4, 4).status)
        assertEquals(Status.DANGER, AbsenceState(5, 4).status)
        assertNull(AbsenceState(9, null).status) // never guessed
        assertEquals("2 left", AbsenceState(6, 8).tag)
        assertEquals("Over limit", AbsenceState(5, 4).tag)
        assertEquals("6 of 8 absences used", AbsenceState(6, 8).line)
        assertEquals("5 absences · limit 4", AbsenceState(5, 4).line)
        assertEquals("1 absence · limit not set", AbsenceState(1, null).line)
        assertEquals("6 of 8", AbsenceState(6, 8).count)
        assertEquals("6", AbsenceState(6, null).count)
    }

    @Test
    fun troubleFirstThenTimetableOrder() {
        assertEquals(
            listOf(2622, 2626, 2615, 2592),
            troubleOrder(att, c.limits, lessons).map { it.course.id },
        )
    }
}
