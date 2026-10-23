package uz.inha.kamol1dn.inha_app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalState
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import java.time.LocalDateTime
import uz.inha.kamol1dn.inha_app.R
import uz.inha.kamol1dn.inha_app.campus.Campus
import uz.inha.kamol1dn.inha_app.campus.CourseLine
import uz.inha.kamol1dn.inha_app.campus.DueRow
import uz.inha.kamol1dn.inha_app.campus.Fmt
import uz.inha.kamol1dn.inha_app.campus.Status
import uz.inha.kamol1dn.inha_app.campus.TapKeys
import uz.inha.kamol1dn.inha_app.campus.Words
import uz.inha.kamol1dn.inha_app.campus.asOf
import uz.inha.kamol1dn.inha_app.campus.attendancePlan
import uz.inha.kamol1dn.inha_app.campus.courseName
import uz.inha.kamol1dn.inha_app.campus.eclassMissing
import uz.inha.kamol1dn.inha_app.campus.eclassStaleAfter

/**
 * "Attendance": absences per course against the limits the student set, courses in trouble
 * first, then the unwatched VOD windows closing within 72 h (a missed one is an absence), then
 * the other courses. Each row taps through to its course or its VOD.
 */
class AttendanceWidget : GlanceAppWidget() {
    // Exact: every Fraunces line's width budget comes from the real size.
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            LocalState.current // read so that every update() recomposes and the cache is read again
            AttendanceContent(Campus.read(context), LocalDateTime.now())
        }
    }
}

class AttendanceWidgetReceiver : PaperWidgetReceiver() {
    override val glanceAppWidget = AttendanceWidget()
}

private sealed interface Entry {
    data class Header(val text: String) : Entry
    data class Course(val line: CourseLine, val ruled: Boolean) : Entry
    data class Vod(val row: DueRow, val ruled: Boolean) : Entry
    data class Note(val text: String, val status: Status? = null) : Entry
}

@Composable
fun AttendanceContent(c: Campus, now: LocalDateTime) {
    val att = c.attendance?.value
    val entries = buildList<Entry> {
        if (att == null) {
            add(Entry.Note(eclassMissing(c.eclassAccount, "attendance")))
            return@buildList
        }
        if (c.eclassAccount?.ok == false) add(Entry.Note("eClass sign-in needed.", Status.DANGER))
        if (att.isEmpty()) add(Entry.Note("No courses in eClass."))
        val p = attendancePlan(att, c.deadlines?.value.orEmpty(), c.lessons?.value.orEmpty(), c.limits, now)
        p.trouble.forEachIndexed { i, l -> add(Entry.Course(l, ruled = i > 0)) }
        if (p.vods.isNotEmpty()) {
            add(Entry.Header("VOD windows closing"))
            p.vods.forEachIndexed { i, r -> add(Entry.Vod(r, ruled = i > 0)) }
        }
        if (p.others.isNotEmpty() && (p.trouble.isNotEmpty() || p.vods.isNotEmpty())) add(Entry.Header("Other courses"))
        p.others.forEachIndexed { i, l -> add(Entry.Course(l, ruled = i > 0)) }
        if (c.limits.isEmpty() && att.any { it.classes.isNotEmpty() }) {
            add(Entry.Note("Set absence limits in the app's Settings to see what is left.", Status.INFO))
        }
    }

    PaperFrame(TapKeys.tab(3)) {
        Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Box(GlanceModifier.defaultWeight()) { PText("Attendance", Face.HEADLINE, maxWidth = lineWidth() - 110.dp) }
            asOf(c.attendance, now, eclassStaleAfter)?.let { StaleMarker(it) }
        }
        Spacer(GlanceModifier.height(8.dp))
        Rule()
        LazyColumn(GlanceModifier.fillMaxWidth().defaultWeight()) {
            items(entries.size) { i -> EntryView(entries[i], now) }
        }
    }
}

@Composable
private fun EntryView(e: Entry, now: LocalDateTime) {
    when (e) {
        is Entry.Header -> Column(GlanceModifier.fillMaxWidth().padding(top = 12.dp, bottom = 2.dp)) {
            PText(e.text, Face.COURSE)
        }
        is Entry.Note -> Column(GlanceModifier.fillMaxWidth().padding(vertical = 8.dp)) {
            if (e.status != null) StatusLine(e.status, e.text, maxLines = 3) else PText(e.text, Face.BODY, maxLines = 3)
        }
        is Entry.Course -> Column(GlanceModifier.fillMaxWidth()) {
            if (e.ruled) Rule()
            CourseRow(e.line, now)
        }
        is Entry.Vod -> Column(GlanceModifier.fillMaxWidth()) {
            if (e.ruled) Rule()
            VodRow(e.row, now)
        }
    }
}

@Composable
private fun CourseRow(line: CourseLine, now: LocalDateTime) {
    val a = line.state
    val status = a.status
    Row(
        GlanceModifier.fillMaxWidth().padding(vertical = 8.dp).clickable(open(TapKeys.course(line.c.course.id))),
        verticalAlignment = Alignment.Top,
    ) {
        Column(GlanceModifier.defaultWeight()) {
            val side = if (line.c.classes.isEmpty()) 0 else maxOf(tallyWidth(a), 48) + 12
            PText(line.c.course.name, Face.COURSE, maxWidth = lineWidth() - side.dp)
            val text = Words.courseLine(line, now)
            if (status != null) StatusLine(status, text) else PText(text, Face.BODY)
            Words.vodLine(line.c)?.let { PText(it, Face.BODY) }
        }
        if (line.c.classes.isNotEmpty()) {
            Spacer(GlanceModifier.width(12.dp))
            Column(
                GlanceModifier.semantics { contentDescription = "${a.count} allowed absences used" },
                horizontalAlignment = Alignment.End,
            ) {
                Tally(a)
                Spacer(GlanceModifier.height(4.dp))
                PText(a.count, Face.NUMERAL, color = status?.color() ?: R.color.w_muted, maxWidth = 64.dp)
            }
        }
    }
}

@Composable
private fun VodRow(r: DueRow, now: LocalDateTime) {
    val d = r.deadline
    Row(
        GlanceModifier.fillMaxWidth().padding(vertical = 8.dp).clickable(open(TapKeys.deadline(d))),
        verticalAlignment = Alignment.Top,
    ) {
        Column(GlanceModifier.defaultWeight()) {
            PText(Fmt.rowTitle(d.title), Face.ITEM)
            val text = Words.dueWarning(d, r.vod, now)
            if (r.status != null) StatusLine(r.status, text, maxLines = 2) else PText(text, Face.BODY, maxLines = 2)
            PText(courseName(d.courseName), Face.BODY)
        }
        Spacer(GlanceModifier.width(12.dp))
        Box(GlanceModifier.width(84.dp), contentAlignment = Alignment.TopEnd) {
            PText(Fmt.relative(d.end, now), Face.NUMERAL, color = r.status?.color(), maxWidth = 84.dp)
        }
    }
}
