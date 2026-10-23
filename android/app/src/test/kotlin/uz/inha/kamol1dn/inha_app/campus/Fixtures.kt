package uz.inha.kamol1dn.inha_app.campus

import java.time.LocalDateTime
import java.time.ZoneId

// Synthetic data in the shape the Flutter app caches. Real IUT course names and rooms,
// nothing from a real account.

val tashkent: ZoneId = ZoneId.of("Asia/Tashkent")

/** Friday 23 October 2026, 13:20. */
val fri: LocalDateTime = LocalDateTime.of(2026, 10, 23, 13, 20)

fun at(day: Int, h: Int, m: Int = 0): LocalDateTime = LocalDateTime.of(2026, 10, day, h, m)

const val lessonsJson = """{"at":"2026-10-23T08:41:00.123456","value":[
 {"weekday":5,"start":"09:00","end":"10:30","subject":"Multimedia Computing","room":"B-305","teacher":"S. Kim","kind":"Lecture"},
 {"weekday":5,"start":"14:00","end":"15:30","subject":"Embedded Software & Design","room":"B202","teacher":"J. Hong","kind":"Lecture"},
 {"weekday":5,"start":"16:00","end":"17:30","subject":"Artificial Intelligence","room":"","teacher":"","kind":""},
 {"weekday":1,"start":"13:00","end":"14:30","subject":"Artificial Intelligence","room":"B101 Conf","teacher":"A. Lee","kind":"Lecture"},
 {"weekday":1,"start":"09:00","end":"10:30","subject":"Multimedia Computing","room":"B-305","teacher":"S. Kim","kind":"Lab"}
]}"""

const val deadlinesJson = """{"at":"2026-10-23T12:00:00.000","value":[
 {"title":"Assignment 1","courseName":"Multimedia Computing","kind":"assignment","start":null,"end":"2026-10-23T23:55:00.000","moduleId":101,"moduleType":"assign","done":false,"doneAt":null},
 {"title":"[QUIZ] 2 Week 6 - 2% (Quiz closes)","courseName":"Artificial Intelligence[202602-AIE3010-001]","kind":"quiz","start":null,"end":"2026-10-24T18:59:00.000Z","moduleId":102,"moduleType":"quiz","done":false,"doneAt":null},
 {"title":"Lab 4","courseName":"Multimedia Computing","kind":"assignment","start":null,"end":"2026-10-22T23:59:00.000","moduleId":103,"moduleType":"assign","done":true,"doneAt":"2026-10-22T21:14:00.000"},
 {"title":"Week 7","courseName":"Distinguished Lecture in Social Science and Art","kind":"vod","start":"2026-10-17T00:00:00.000","end":"2026-10-25T23:59:59.000","moduleId":104,"moduleType":"vod","done":false,"doneAt":null},
 {"title":"Week 6","courseName":"Distinguished Lecture in Social Science and Art","kind":"vod","start":"2026-10-10T00:00:00.000","end":"2026-10-24T23:59:59.000","moduleId":105,"moduleType":"vod","done":false,"doneAt":null},
 {"title":"Artificial Intelligence[001]-3교시","courseName":"Artificial Intelligence","kind":"classPeriod","start":null,"end":"2026-10-23T14:00:00.000","moduleId":null,"moduleType":null,"done":false,"doneAt":null},
 {"title":"Report","courseName":"Embedded Software & Design","kind":"other","start":null,"end":"2026-10-30T23:59:00.000","moduleId":106,"moduleType":"ubboard","done":false,"doneAt":null}
]}"""

const val attendanceJson = """{"at":"2026-10-23T12:00:00.000","value":[
 {"course":{"id":2622,"name":"Artificial Intelligence","code":"AIE3010","professor":"A. Lee"},
  "classes":[
   {"date":"2026-09-07T00:00:00.000","label":"1Class","mark":"absent"},
   {"date":"2026-09-14T00:00:00.000","label":"2Class","mark":"absent"},
   {"date":"2026-09-21T00:00:00.000","label":"3Class","mark":"absent"},
   {"date":"2026-09-28T00:00:00.000","label":"4Class","mark":"absent"},
   {"date":"2026-10-05T00:00:00.000","label":"5Class","mark":"absent"},
   {"date":"2026-10-12T00:00:00.000","label":"6Class","mark":"absent"},
   {"date":"2026-10-19T00:00:00.000","label":"7Class","mark":"present"},
   {"date":"2026-11-02T00:00:00.000","label":"9Class","mark":"unmarked"}],
  "vods":[]},
 {"course":{"id":2626,"name":"Multimedia Computing","code":"SOC4020","professor":"S. Kim"},
  "classes":[
   {"date":"2026-09-08T00:00:00.000","label":"1Class","mark":"absent"},
   {"date":"2026-09-15T00:00:00.000","label":"2Class","mark":"present"},
   {"date":"2026-09-22T00:00:00.000","label":"3Class","mark":"late"}],
  "vods":[]},
 {"course":{"id":2592,"name":"Distinguished Lecture in Social Science and Art","code":"GEN1001","professor":""},
  "classes":[],
  "vods":[
   {"week":6,"title":"Week 6","lengthSec":4500,"percent":100.0},
   {"week":7,"title":"Week 7","lengthSec":4500,"percent":62.4}]},
 {"course":{"id":2615,"name":"Embedded Software & Design","code":"ICE4030","professor":"J. Hong"},
  "classes":[{"date":"2026-09-09T00:00:00.000","label":"1Class","mark":"present"}],
  "vods":[]}
]}"""

const val gradesJson = """{"at":"2026-10-22T18:04:00.000","value":{"gpa":3.87,"creditsEarned":98.0,"yearOfStudy":3,"records":[
 {"term":"2026 Spring Semester","termKey":20261,"code":"SOC3010","name":"Computer Networks","credits":3.0,"letter":"A+","points":4.5,"category":"MR-M"},
 {"term":"2026 Spring Semester","termKey":20261,"code":"SOC3020","name":"Operating Systems","credits":3.0,"letter":"B+","points":3.5,"category":"MR-M"},
 {"term":"2025 Fall Semester","termKey":20252,"code":"GEN2010","name":"Academic English","credits":2.0,"letter":"A0","points":4.0,"category":"GR"},
 {"term":"2026 Fall Semester","termKey":20262,"code":"SOC4020","name":"Multimedia Computing","credits":3.0,"letter":"-","points":0.0,"category":"MR-M"}
]}}"""

/** The app's prefs as the plugin stores them, minus the `flutter.` prefix. */
fun prefs(vararg extra: Pair<String, String?>): Map<String, String?> = mapOf(
    "cache.lessons" to lessonsJson,
    "cache.deadlines" to deadlinesJson,
    "cache.attendance" to attendanceJson,
    "cache.grades" to gradesJson,
    "absenceLimits.v1" to """{"2622":8,"2626":8,"bad":3,"2615":"x"}""",
    "account.eclass" to """{"ok":true,"at":"2026-10-23T12:00:00.000"}""",
    "account.ins" to """{"ok":false,"at":"2026-10-22T18:04:00.000"}""",
) + extra

fun campus(vararg extra: Pair<String, String?>): Campus {
    val p = prefs(*extra)
    return Campus.from({ p[it] }, tashkent)
}
