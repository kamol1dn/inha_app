package uz.inha.kamol1dn.inha_app.campus

import java.time.Duration
import java.time.LocalDateTime

// Every user-visible time and date string on the Android side (DESIGN.md 9), the same as
// lib/ui/format/format.dart, plus the name matching the app uses.

/** Dart's (JavaScript's) `\s`, which is wider than Java's: it includes no-break and ideographic spaces. */
private const val WS = "[\\s\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]"
private val spaces = Regex("$WS+")
private val edges = Regex("^$WS+|$WS+$")

/** Dart's `trim()`. */
fun dartTrim(s: String) = s.replace(edges, "")

/** Runs of whitespace become one space, trimmed. */
fun clean(s: String) = dartTrim(s.replace(spaces, " "))

/** Case and spacing ignored, for matching names. */
fun norm(s: String) = clean(s).lowercase()

private val courseTitle = Regex("^(.*?)\\s*\\[\\d+-([A-Z]+\\d+)-\\d+][\\s\\S]*$")

/**
 * A course name without eClass's "[202602-SOC4020-001]" suffix (and a "NEW" badge after it),
 * should one slip through (`Course.fromTitle` and `_courseName` in the app): names, never codes.
 */
fun courseName(s: String): String {
    val title = clean(s)
    val m = courseTitle.find(title)
    return clean(m?.groupValues?.get(1) ?: title)
}

/** The code in such a suffix ("SOC4040"), or null. */
fun courseCode(s: String): String? = courseTitle.find(clean(s))?.groupValues?.get(2)

private val wd = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
private val mon = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

private fun pad(n: Int) = n.toString().padStart(2, '0')

object Fmt {
    /** 09:00 */
    fun clock(t: LocalDateTime) = "${pad(t.hour)}:${pad(t.minute)}"

    /** 10:30–11:50 */
    fun range(a: LocalDateTime, b: LocalDateTime) = "${clock(a)}–${clock(b)}"

    fun weekdayShort(weekday: Int) = wd[weekday - 1]

    /** Thu 23 Oct (the year only when it isn't this year) */
    fun dayDate(t: LocalDateTime, now: LocalDateTime): String {
        val y = if (t.year == now.year) "" else " ${t.year}"
        return "${wd[t.dayOfWeek.value - 1]} ${t.dayOfMonth} ${mon[t.monthValue - 1]}$y"
    }

    /** Today / Tomorrow / Sat 25 Oct */
    fun dayHeader(t: LocalDateTime, now: LocalDateTime): String =
        when (Duration.between(now.toLocalDate().atStartOfDay(), t.toLocalDate().atStartOfDay()).toDays()) {
            0L -> "Today"
            1L -> "Tomorrow"
            else -> dayDate(t, now)
        }

    /** 1 h 10 min / 40 min */
    fun duration(d: Duration): String {
        val h = d.toHours()
        val m = d.toMinutes() % 60
        if (h == 0L) return "$m min"
        if (m == 0L) return "$h h"
        return "$h h $m min"
    }

    /** now / in 25 min / in 2 h 15 min / in 6 h / Sat 23:59 / 3 Nov 23:59 / Overdue 2 h */
    fun relative(t: LocalDateTime, now: LocalDateTime): String {
        val d = Duration.between(now, t)
        if (d.isNegative) {
            val p = d.negated()
            if (p.toHours() < 24) return if (p.toMinutes() < 60) "Overdue ${p.toMinutes()} min" else "Overdue ${p.toHours()} h"
            return "Overdue ${p.toDays()} d"
        }
        if (d.toMinutes() < 1) return "now"
        if (d.toMinutes() < 60) return "in ${d.toMinutes()} min"
        if (d.toHours() < 3) return "in ${duration(d)}"
        if (d.toHours() < 24) return "in ${d.toHours()} h"
        if (d.toDays() < 7) return "${wd[t.dayOfWeek.value - 1]} ${clock(t)}"
        return "${t.dayOfMonth} ${mon[t.monthValue - 1]} ${clock(t)}"
    }

    /** 08:41 today, otherwise Tue 18:04 */
    fun updatedAt(t: LocalDateTime, now: LocalDateTime) =
        if (t.toLocalDate() == now.toLocalDate()) clock(t) else "${wd[t.dayOfWeek.value - 1]} ${clock(t)}"

    private val kindTag = Regex("^\\[([A-Za-z]{2,12})]$WS*")
    private val eventSuffix =
        Regex("$WS*(\\((\\w+$WS+)?(opens|closes|is due|due|starts|ends)\\)|$WS+is due)$WS*$", RegexOption.IGNORE_CASE)

    /**
     * An eClass title as a row shows it (DESIGN.md 7): "[QUIZ] 2 Week 6 - 2% (Quiz closes)" reads
     * "Quiz 2 Week 6 - 2%". Mirrors `rowTitle` in lib/ui/format/format.dart.
     */
    fun rowTitle(title: String): String {
        var t = dartTrim(title).replaceFirst(eventSuffix, "")
        val tag = kindTag.find(t)
        if (tag != null) {
            val rest = t.substring(tag.range.last + 1)
            val word = tag.groupValues[1]
            t = if (rest.firstOrNull() in '0'..'9') {
                word[0].uppercase() + word.substring(1).lowercase() + " " + rest
            } else {
                rest
            }
        }
        t = dartTrim(t.replace(spaces, " "))
        return t.ifEmpty { dartTrim(title) }
    }
}
