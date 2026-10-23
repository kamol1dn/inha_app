package uz.inha.kamol1dn.inha_app.campus

import android.content.Context
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import org.json.JSONArray
import org.json.JSONObject

/**
 * Everything the widgets and AppFunctions need, read straight from the Flutter app's
 * SharedPreferences file. Nothing here starts the Dart engine.
 *
 * The app keeps each source as `cache.<key>` = `{"at": ..., "value": ...}` (lib/core/cache.dart),
 * the absence limits as `absenceLimits.v1` and the last login result per service as
 * `account.<service>` (lib/data/app_data.dart, `Prefs`). The shared_preferences plugin stores
 * them in `FlutterSharedPreferences.xml` with a `flutter.` prefix. A value that doesn't parse
 * counts as missing, as it does in the app.
 */
class Campus(
    val lessons: Cached<List<Lesson>>?,
    val deadlines: Cached<List<Deadline>>?,
    val attendance: Cached<List<CourseAttendance>>?,
    val grades: Cached<GradeReport>?,
    /** Allowed absences per eClass course id, as the student set them. */
    val limits: Map<Int, Int>,
    val eclassAccount: AccountCheck?,
    val insAccount: AccountCheck?,
) {
    companion object {
        const val PREFS_FILE = "FlutterSharedPreferences"
        private const val PREFIX = "flutter."

        fun read(context: Context): Campus {
            val prefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            return from(get = { key ->
                try {
                    prefs.getString(PREFIX + key, null)
                } catch (_: ClassCastException) {
                    null
                }
            })
        }

        /** [get] returns the stored string for an app key (without the `flutter.` prefix). */
        fun from(get: (String) -> String?, zone: ZoneId = ZoneId.systemDefault()): Campus {
            val parse = CacheJson(zone)
            return Campus(
                lessons = parse.cached(get("cache.lessons")) { parse.list(it, parse::lesson) },
                deadlines = parse.cached(get("cache.deadlines")) { parse.list(it, parse::deadline) },
                attendance = parse.cached(get("cache.attendance")) { parse.list(it, parse::courseAttendance) },
                grades = parse.cached(get("cache.grades")) { parse.gradeReport(it as JSONObject) },
                limits = parse.limits(get("absenceLimits.v1")),
                eclassAccount = parse.account(get("account.eclass")),
                insAccount = parse.account(get("account.ins")),
            )
        }
    }
}

/** The JSON the Dart models write (`toJson` in lib/models/models.dart). */
internal class CacheJson(private val zone: ZoneId) {

    fun <T> cached(raw: String?, decode: (Any) -> T): Cached<T>? {
        if (raw == null) return null
        return try {
            val j = JSONObject(raw)
            Cached(decode(j.get("value")), time(j.getString("at")))
        } catch (_: Exception) {
            null // shape changed between app versions; the app refetches it
        }
    }

    fun <T> list(json: Any, item: (JSONObject) -> T): List<T> {
        val a = json as JSONArray
        return List(a.length()) { item(a.getJSONObject(it)) }
    }

    /**
     * Dart's `toIso8601String`: local times have no zone ("2026-10-25T23:59:59.000"), UTC ones
     * end in Z. Either way the result is local wall-clock time in [zone].
     */
    fun time(s: String): LocalDateTime {
        val hasZone = s.endsWith("Z") || Regex("[+-]\\d\\d:?\\d\\d$").containsMatchIn(s.substringAfter('T'))
        return if (hasZone) OffsetDateTime.parse(s).atZoneSameInstant(zone).toLocalDateTime() else LocalDateTime.parse(s)
    }

    private fun JSONObject.str(key: String) = if (isNull(key)) "" else optString(key, "")
    private fun JSONObject.timeOrNull(key: String) = if (isNull(key)) null else time(getString(key))
    private fun JSONObject.intOrNull(key: String) = if (isNull(key)) null else getInt(key)

    fun lesson(j: JSONObject) = Lesson(
        weekday = j.getInt("weekday"),
        start = j.getString("start"),
        end = j.getString("end"),
        subject = j.getString("subject"),
        room = j.str("room"),
        teacher = j.str("teacher"),
        kind = j.str("kind"),
    )

    fun deadline(j: JSONObject) = Deadline(
        title = j.getString("title"),
        courseName = j.getString("courseName"),
        kind = DeadlineKind.of(j.getString("kind")),
        start = j.timeOrNull("start"),
        end = time(j.getString("end")),
        moduleId = j.intOrNull("moduleId"),
        moduleType = if (j.isNull("moduleType")) null else j.getString("moduleType"),
        done = j.optBoolean("done", false),
        doneAt = j.timeOrNull("doneAt"),
    )

    fun course(j: JSONObject) = Course(
        id = j.getInt("id"),
        name = j.getString("name"),
        code = j.str("code"),
        professor = j.str("professor"),
    )

    fun courseAttendance(j: JSONObject) = CourseAttendance(
        course = course(j.getJSONObject("course")),
        classes = list(j.getJSONArray("classes")) {
            AttendanceEntry(
                date = time(it.getString("date")),
                label = it.getString("label"),
                mark = AttendanceMark.valueOf(it.getString("mark").uppercase()),
            )
        },
        vods = list(j.getJSONArray("vods")) {
            VodProgress(
                week = it.getInt("week"),
                title = it.getString("title"),
                lengthSec = it.getInt("lengthSec"),
                percent = it.getDouble("percent"),
            )
        },
    )

    fun gradeReport(j: JSONObject) = GradeReport(
        gpa = j.getDouble("gpa"),
        creditsEarned = j.getDouble("creditsEarned"),
        yearOfStudy = j.getInt("yearOfStudy"),
        records = list(j.getJSONArray("records")) {
            GradeRecord(
                term = it.getString("term"),
                termKey = it.getInt("termKey"),
                code = it.str("code"),
                name = it.getString("name"),
                credits = it.getDouble("credits"),
                letter = it.getString("letter"),
                points = it.getDouble("points"),
            )
        },
    )

    /** `{"2622": 8}`: course id to allowed absences. Anything malformed is skipped. */
    fun limits(raw: String?): Map<Int, Int> {
        if (raw == null) return emptyMap()
        return try {
            val j = JSONObject(raw)
            buildMap {
                for (key in j.keys()) {
                    val id = key.toIntOrNull() ?: continue
                    val v = j.get(key)
                    if (v is Int) put(id, v)
                }
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun account(raw: String?): AccountCheck? {
        if (raw == null) return null
        return try {
            val j = JSONObject(raw)
            AccountCheck(j.optBoolean("ok", false), time(j.getString("at")))
        } catch (_: Exception) {
            null
        }
    }
}
