package uz.inha.kamol1dn.inha_app.campus

import android.net.Uri
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * What a widget tap opens, as the key a notification tap carries (lib/notifications/rules.dart),
 * so the app routes both the same way (lib/notifications/routes.dart). The app's HomeShell takes
 * the key from `iut://open?key=...`.
 */
object TapKeys {
    /** Opens the item's sheet over Deadlines; the app matches it on `reminderStem` + "|". */
    fun deadline(d: Deadline, zone: ZoneId = ZoneId.systemDefault()) = "${reminderStem(d, zone)}|widget"

    /** Opens the course over Courses. */
    fun course(courseId: Int) = "absent:$courseId|widget"

    /** Opens Schedule on that day. */
    fun schedule(day: LocalDate) = "class:$day|widget"

    /** Opens a tab: 0 Today, 1 Schedule, 2 Deadlines, 3 Courses. */
    fun tab(index: Int) = "tab:$index"

    fun uri(key: String): Uri = Uri.Builder().scheme("iut").authority("open").appendQueryParameter("key", key).build()

    /** `reminderStem` in lib/notifications/rules.dart. */
    fun reminderStem(d: Deadline, zone: ZoneId = ZoneId.systemDefault()): String {
        val item = "${norm(courseName(d.courseName))}|${norm(d.title)}|${stamp(d.end, zone)}"
        return if (d.kind == DeadlineKind.VOD) "vod:$item" else "due:${d.kind.wire}:$item"
    }

    /** Minute-precision UTC, as `_stamp` writes it: 20261025T1859Z. */
    fun stamp(t: LocalDateTime, zone: ZoneId): String {
        val u = t.atZone(zone).withZoneSameInstant(ZoneOffset.UTC)
        fun two(n: Int) = n.toString().padStart(2, '0')
        return "${u.year}${two(u.monthValue)}${two(u.dayOfMonth)}T${two(u.hour)}${two(u.minute)}Z"
    }
}
