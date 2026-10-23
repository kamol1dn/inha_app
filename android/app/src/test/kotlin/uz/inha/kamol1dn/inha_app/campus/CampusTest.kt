package uz.inha.kamol1dn.inha_app.campus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CampusTest {
    @Test
    fun readsEverySource() {
        val c = campus()
        assertEquals(5, c.lessons!!.value.size)
        assertEquals(at(23, 8, 41).plusNanos(123_456_000), c.lessons!!.at)
        assertEquals(7, c.deadlines!!.value.size)
        assertEquals(4, c.attendance!!.value.size)
        assertEquals(3.87, c.grades!!.value.gpa, 0.0)
        assertEquals(4, c.grades!!.value.records.size)
    }

    @Test
    fun lessonFields() {
        val l = campus().lessons!!.value[1]
        assertEquals(Lesson(5, "14:00", "15:30", "Embedded Software & Design", "B202", "J. Hong", "Lecture"), l)
    }

    @Test
    fun localTimesStayLocalAndUtcTimesAreConverted() {
        val d = campus().deadlines!!.value
        assertEquals(at(23, 23, 55), d[0].end)
        // "2026-10-24T18:59:00.000Z" is 23:59 in Tashkent (UTC+5).
        assertEquals(at(24, 23, 59), d[1].end)
        assertEquals(DeadlineKind.QUIZ, d[1].kind)
        assertEquals(102, d[1].moduleId)
    }

    @Test
    fun deadlineDoneAndKinds() {
        val d = campus().deadlines!!.value
        assertTrue(d[2].done)
        assertEquals(at(22, 21, 14), d[2].doneAt)
        assertEquals(DeadlineKind.CLASS_PERIOD, d[5].kind)
        assertNull(d[5].moduleId)
        assertEquals(at(17, 0), d[3].start)
    }

    @Test
    fun attendanceMarksAndVods() {
        val a = campus().attendance!!.value
        assertEquals(6, a[0].count(AttendanceMark.ABSENT))
        assertEquals(AttendanceMark.LATE, a[1].classes[2].mark)
        assertEquals(62.4, a[2].vods[1].percent, 0.0)
        assertFalse(a[2].vods[1].done)
        assertTrue(a[2].vods[0].done)
    }

    @Test
    fun limitsSkipMalformedEntries() {
        assertEquals(mapOf(2622 to 8, 2626 to 8), campus().limits)
    }

    @Test
    fun accounts() {
        val c = campus()
        assertTrue(c.eclassAccount!!.ok)
        assertFalse(c.insAccount!!.ok)
        assertEquals(at(22, 18, 4), c.insAccount!!.at)
    }

    @Test
    fun missingOrBrokenCacheIsNull() {
        val c = campus("cache.lessons" to null, "cache.deadlines" to "{not json", "cache.grades" to """{"at":"2026-10-22T18:04:00.000","value":{"gpa":"x"}}""")
        assertNull(c.lessons)
        assertNull(c.deadlines)
        assertNull(c.grades)
        assertEquals(4, c.attendance!!.value.size)
    }

    @Test
    fun nothingStoredAtAll() {
        val c = Campus.from({ null }, tashkent)
        assertNull(c.lessons)
        assertNull(c.attendance)
        assertEquals(emptyMap<Int, Int>(), c.limits)
        assertNull(c.eclassAccount)
    }
}
