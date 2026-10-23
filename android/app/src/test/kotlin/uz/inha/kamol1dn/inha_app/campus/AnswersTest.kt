package uz.inha.kamol1dn.inha_app.campus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AnswersTest {
    private val c = campus()
    private val lessons = c.lessons!!.value
    private val deadlines = c.deadlines!!.value
    private val att = c.attendance!!.value

    @Test
    fun upNextIsTheNextClassAndTheNextOpenItem() {
        val u = upNext(lessons, deadlines, att, c.limits, fri)
        assertEquals("B202", u.slot!!.lesson.room)
        assertFalse(u.current)
        assertNull(u.trouble)
        assertEquals("Assignment 1", u.due!!.title)
        assertEquals("Next · in 40 min", Words.classLabel(u.slot!!, fri))
    }

    @Test
    fun upNextCarriesTheCoursesAttendanceTrouble() {
        val u = upNext(lessons, deadlines, att, c.limits, at(23, 15, 45))
        assertEquals("Artificial Intelligence", u.slot!!.lesson.subject)
        assertEquals(Status.WARNING, u.trouble!!.status)
        assertEquals("6 of 8 absences used · 2 left", Words.absenceWarning(u.trouble!!))
    }

    @Test
    fun classLabels() {
        val now = at(23, 14, 50)
        val s = nextLesson(lessons, now)!!
        assertEquals("Now · until 15:30 · 40 min left", Words.classLabel(s, now))
        val evening = at(23, 18)
        assertEquals("Next · Mon 26 Oct 09:00", Words.classLabel(nextLesson(lessons, evening)!!, evening))
    }

    @Test
    fun todayInTimeOrder() {
        val p = todayPlan(lessons, deadlines, att, c.limits, fri)
        assertTrue(p.overdue.isEmpty())
        val rows = p.rows
        assertEquals(4, rows.size)
        assertEquals("Embedded Software & Design", (rows[0] as ClassRow).slot.lesson.subject)
        val ai = rows[1] as ClassRow
        assertEquals("Artificial Intelligence", ai.slot.lesson.subject)
        assertEquals(Status.WARNING, ai.trouble!!.status)
        assertEquals(NoteRow(NoteKind.FREE_AFTER, at(23, 17, 30)), rows[2])
        val due = rows[3] as DueRow
        assertEquals("Assignment 1", due.deadline.title)
        assertEquals(Status.WARNING, due.status)
        assertEquals("Due in 10 h · not submitted", Words.dueLine(due, fri))
        assertNull(p.next)
    }

    @Test
    fun todayAfterTheLastClassPointsToTheNextDay() {
        val p = todayPlan(lessons, deadlines, att, c.limits, at(23, 18))
        assertEquals(NoteRow(NoteKind.NO_MORE_CLASSES, null), p.rows.first())
        assertEquals(at(26, 9), p.next!!.start)
    }

    @Test
    fun todayOnTheWeekendAndOverdue() {
        val sat = at(24, 9)
        val p = todayPlan(lessons, deadlines, att, c.limits, sat)
        assertEquals("Assignment 1", p.overdue.single().deadline.title)
        assertEquals("Overdue 9 h · not submitted", Words.dueLine(p.overdue.single(), sat))
        assertEquals(NoteRow(NoteKind.NO_CLASSES, null), p.rows.first())
        assertEquals("[QUIZ] 2 Week 6 - 2% (Quiz closes)", (p.rows[1] as DueRow).deadline.title)
    }

    @Test
    fun todayWithoutATimetableClaimsNothing() {
        val p = todayPlan(null, deadlines, att, c.limits, fri)
        assertTrue(p.rows.none { it is NoteRow })
        assertEquals(1, p.rows.size)
    }

    @Test
    fun attendanceTroubleFirstThenVodWindowsThenTheRest() {
        val p = attendancePlan(att, deadlines, lessons, c.limits, fri)
        assertEquals(listOf(2622), p.trouble.map { it.c.course.id })
        assertEquals("2 left · next today 16:00", Words.courseLine(p.trouble.single(), fri))
        val vod = p.vods.single()
        assertEquals("Week 7", vod.deadline.title)
        assertEquals("62% watched, 29 min left", Words.dueLine(vod, fri))
        assertEquals(listOf(2626, 2615, 2592), p.others.map { it.c.course.id })
        assertEquals("Next Mon 09:00 · B-305", Words.courseLine(p.others[0], fri))
        assertEquals("Limit not set · Today 14:00 · B202", Words.courseLine(p.others[1], fri))
        assertEquals("No class attendance in eClass", Words.courseLine(p.others[2], fri))
        assertEquals("VOD 1 of 2 watched", Words.vodLine(p.others[2].c))
    }

    @Test
    fun widgetsRedrawWhenTheClockChangesWhatTheySay() {
        // 13:20, next class 14:00: the countdown moves every 5 minutes.
        assertEquals(at(23, 13, 25), nextTick(lessons, deadlines, att, fri))
        // 10:40, next class 14:00 (3 h 20 min): every 30 minutes.
        assertEquals(at(23, 11, 10), nextTick(lessons, deadlines, att, at(23, 10, 40)))
        // 13:58: the class starts before the next 5-minute step.
        assertEquals(at(23, 14, 0), nextTick(lessons, deadlines, att, at(23, 13, 58)))
        // Saturday 23:30, no class until Monday: Assignment 1 drops off at 23:55, a day overdue.
        assertEquals(at(23, 23, 55).plusHours(24), nextTick(lessons, deadlines, att, at(24, 23, 30)))
        // Never sooner than a minute ahead: 15 s before a class, the redraw comes just after it starts.
        assertEquals(at(23, 14, 0).plusSeconds(45), nextTick(lessons, deadlines, att, at(23, 13, 59).plusSeconds(45)))
    }

    @Test
    fun staleMarkersAndMissingData() {
        assertNull(staleNote("Timetable", c.lessons, fri, timetableStaleAfter))
        assertEquals("Timetable as of Fri 08:41", staleNote("Timetable", c.lessons, at(24, 8, 42), timetableStaleAfter))
        assertEquals("as of 12:00", asOf(c.deadlines, at(23, 15, 1), eclassStaleAfter))
        assertEquals("Sign in to eClass in the app to see deadlines.", eclassMissing(null, "deadlines"))
        assertEquals("Sign in to eClass in the app to see deadlines.", eclassMissing(AccountCheck(false, fri), "deadlines"))
        assertEquals("Open the app to load attendance from eClass.", eclassMissing(AccountCheck(true, fri), "attendance"))
    }

    @Test
    fun dueWhenWithoutATimeColumn() {
        assertEquals("Due Sat 23:59 · not attempted", Words.dueWhen(deadlines[1], null, fri))
        val week7 = deadlines[3]
        assertEquals("Closes Sun 23:59 · 62% watched", Words.dueWhen(week7, vodFor(week7, att), fri))
    }

    @Test
    fun plainDueLines() {
        val quiz = DueRow(deadlines[1], null, null)
        // Names, never codes: eClass's "[202602-AIE3010-001]" suffix goes.
        assertEquals("Not attempted · Artificial Intelligence", Words.dueLine(quiz, fri))
        val report = DueRow(deadlines.last(), null, null)
        assertEquals("Embedded Software & Design", Words.dueLine(report, fri))
    }
}
