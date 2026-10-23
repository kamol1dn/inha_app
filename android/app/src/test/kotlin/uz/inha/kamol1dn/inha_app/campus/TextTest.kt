package uz.inha.kamol1dn.inha_app.campus

import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Test

class TextTest {
    @Test
    fun rowTitleMatchesTheApp() {
        // The same cases as test/format_test.dart.
        assertEquals("Quiz 2 Week 6 - 2%", Fmt.rowTitle("[QUIZ] 2 Week 6 - 2% (Quiz closes)"))
        assertEquals("Midterm review", Fmt.rowTitle("[QUIZ] Midterm review (Quiz opens)"))
        assertEquals("Week 7 lecture", Fmt.rowTitle("[VOD]  Week 7  lecture"))
        assertEquals("Lab 5", Fmt.rowTitle("Lab 5 is due"))
        assertEquals("Essay draft", Fmt.rowTitle("Essay draft (Assignment due)"))
        assertEquals("Peer review", Fmt.rowTitle("Peer review (Workshop closes)"))
        assertEquals("Reading list", Fmt.rowTitle("Reading list (closes)"))
        assertEquals("Assignment 1", Fmt.rowTitle("Assignment 1"))
        assertEquals("Report (due Friday)", Fmt.rowTitle("Report (due Friday)"))
        assertEquals("Lab 3 [group work]", Fmt.rowTitle("Lab 3 [group work]"))
        assertEquals("[2026] Final project", Fmt.rowTitle("[2026] Final project"))
        assertEquals("[QUIZ] (Quiz closes)", Fmt.rowTitle("[QUIZ] (Quiz closes)"))
    }

    @Test
    fun relativeTimes() {
        assertEquals("now", Fmt.relative(fri.plusSeconds(30), fri))
        assertEquals("in 25 min", Fmt.relative(fri.plusMinutes(25), fri))
        assertEquals("in 2 h 15 min", Fmt.relative(fri.plusMinutes(135), fri))
        assertEquals("in 6 h", Fmt.relative(fri.plusHours(6).plusMinutes(20), fri))
        assertEquals("Sat 23:59", Fmt.relative(at(24, 23, 59), fri))
        assertEquals("3 Nov 23:59", Fmt.relative(at(23, 23, 59).plusDays(11), fri))
        assertEquals("Overdue 40 min", Fmt.relative(fri.minusMinutes(40), fri))
        assertEquals("Overdue 2 h", Fmt.relative(fri.minusHours(2), fri))
        assertEquals("Overdue 2 d", Fmt.relative(fri.minusDays(2), fri))
    }

    @Test
    fun datesAndDurations() {
        assertEquals("Fri 23 Oct", Fmt.dayDate(fri, fri))
        assertEquals("Fri 1 Jan 2027", Fmt.dayDate(fri.withYear(2027).withMonth(1).withDayOfMonth(1), fri))
        assertEquals("Today", Fmt.dayHeader(at(23, 23), fri))
        assertEquals("Tomorrow", Fmt.dayHeader(at(24, 1), fri))
        assertEquals("Sun 25 Oct", Fmt.dayHeader(at(25, 9), fri))
        assertEquals("1 h 10 min", Fmt.duration(Duration.ofMinutes(70)))
        assertEquals("40 min", Fmt.duration(Duration.ofMinutes(40)))
        assertEquals("2 h", Fmt.duration(Duration.ofHours(2)))
        assertEquals("13:20", Fmt.updatedAt(fri, fri))
        assertEquals("Thu 18:04", Fmt.updatedAt(at(22, 18, 4), fri))
    }

    @Test
    fun namesCompareLikeDart() {
        assertEquals("multimedia computing", norm("  Multimedia  Computing　"))
        assertEquals("a b", clean("a \t\n b"))
    }
}
