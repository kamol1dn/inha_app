package uz.inha.kamol1dn.inha_app.campus

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Test

class TapKeysTest {
    private val deadlines = campus().deadlines!!.value

    @Test
    fun deadlineKeysStartWithTheAppsReminderStem() {
        // The same string test/widget_keys_test.dart expects from reminderStem in Dart.
        assertEquals(
            "due:quiz:artificial intelligence|[quiz] 2 week 6 - 2% (quiz closes)|20261024T1859Z",
            TapKeys.reminderStem(deadlines[1], tashkent),
        )
        assertEquals(
            "due:quiz:artificial intelligence|[quiz] 2 week 6 - 2% (quiz closes)|20261024T1859Z|widget",
            TapKeys.deadline(deadlines[1], tashkent),
        )
        assertEquals(
            "vod:distinguished lecture in social science and art|week 7|20261025T1859Z",
            TapKeys.reminderStem(deadlines[3], tashkent),
        )
    }

    @Test
    fun courseNameDropsTheEclassSuffix() {
        assertEquals("Artificial Intelligence", courseName("Artificial Intelligence[202602-AIE3010-001]"))
        assertEquals("Lab Course", courseName("Lab  Course"))
        assertEquals("Embedded Software & Design", courseName(" Embedded  Software & Design "))
    }

    @Test
    fun otherKeys() {
        assertEquals("absent:2622|widget", TapKeys.course(2622))
        assertEquals("class:2026-10-26|widget", TapKeys.schedule(LocalDate.of(2026, 10, 26)))
        assertEquals("tab:3", TapKeys.tab(3))
    }
}
