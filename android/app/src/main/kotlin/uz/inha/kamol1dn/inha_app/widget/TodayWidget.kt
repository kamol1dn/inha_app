package uz.inha.kamol1dn.inha_app.widget

import android.content.Context
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalState
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.unit.ColorProvider
import java.time.LocalDateTime
import uz.inha.kamol1dn.inha_app.R
import uz.inha.kamol1dn.inha_app.campus.Campus
import uz.inha.kamol1dn.inha_app.campus.ClassRow
import uz.inha.kamol1dn.inha_app.campus.DueRow
import uz.inha.kamol1dn.inha_app.campus.Fmt
import uz.inha.kamol1dn.inha_app.campus.NoteKind
import uz.inha.kamol1dn.inha_app.campus.NoteRow
import uz.inha.kamol1dn.inha_app.campus.Status
import uz.inha.kamol1dn.inha_app.campus.TapKeys
import uz.inha.kamol1dn.inha_app.campus.TodayRow
import uz.inha.kamol1dn.inha_app.campus.Words
import uz.inha.kamol1dn.inha_app.campus.courseName
import uz.inha.kamol1dn.inha_app.campus.eclassMissing
import uz.inha.kamol1dn.inha_app.campus.eclassStaleAfter
import uz.inha.kamol1dn.inha_app.campus.staleNote
import uz.inha.kamol1dn.inha_app.campus.timetableStaleAfter
import uz.inha.kamol1dn.inha_app.campus.todayPlan

/**
 * "Today": the rest of today's classes and what is due today, on a small rail like the app's
 * Today screen, with overdue items first. When today has no more classes it says so and names
 * the next one.
 */
class TodayWidget : GlanceAppWidget() {
    // Exact: every Fraunces line's width budget comes from the real size.
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            LocalState.current // read so that every update() recomposes and the cache is read again
            TodayContent(Campus.read(context), LocalDateTime.now())
        }
    }
}

class TodayWidgetReceiver : PaperWidgetReceiver() {
    override val glanceAppWidget = TodayWidget()
}

/** One line on the widget's rail, top to bottom. */
private sealed interface Line {
    data class Header(val text: String, val status: Status?) : Line
    data class Note(val text: String, val key: String? = null, val status: Status? = null) : Line
    data class Item(val row: TodayRow, val lineAbove: Boolean, val lineBelow: Boolean) : Line
}

@Composable
fun TodayContent(c: Campus, now: LocalDateTime) {
    val att = c.attendance?.value.orEmpty()
    val plan = todayPlan(c.lessons?.value, c.deadlines?.value.orEmpty(), att, c.limits, now)

    val lines = buildList<Line> {
        staleNote("Timetable", c.lessons, now, timetableStaleAfter)?.let { add(Line.Note(it, status = Status.WARNING)) }
        when {
            c.deadlines == null -> add(Line.Note(eclassMissing(c.eclassAccount, "deadlines"), TapKeys.tab(0)))
            c.eclassAccount?.ok == false -> add(Line.Note("eClass sign-in needed.", TapKeys.tab(0), Status.DANGER))
            else -> staleNote("eClass", c.deadlines, now, eclassStaleAfter)?.let { add(Line.Note(it, status = Status.WARNING)) }
        }
        if (c.lessons == null) add(Line.Note("Open the app to load the timetable.", TapKeys.tab(1)))
        if (plan.overdue.isNotEmpty()) {
            add(Line.Header("Overdue", Status.DANGER))
            plan.overdue.forEachIndexed { i, r -> add(Line.Item(r, i > 0, i < plan.overdue.lastIndex)) }
        }
        plan.rows.forEachIndexed { i, r -> add(Line.Item(r, i > 0, i < plan.rows.lastIndex)) }
        if (plan.tomorrow.isNotEmpty()) {
            // Due after midnight but within 24 h, so work due at 00:00 shows the evening before.
            add(Line.Header("Tomorrow", null))
            plan.tomorrow.forEachIndexed { i, r -> add(Line.Item(r, i > 0, i < plan.tomorrow.lastIndex)) }
        }
        plan.next?.let { s ->
            val room = s.lesson.room.ifEmpty { "room not set" }
            add(Line.Note("Next: ${Fmt.dayDate(s.start, now)}, ${s.lesson.start} ${s.lesson.subject}, $room.", TapKeys.schedule(s.day)))
        }
    }

    PaperFrame(TapKeys.tab(0)) {
        PText(Fmt.dayDate(now, now), Face.HEADLINE)
        Spacer(GlanceModifier.height(8.dp))
        Rule()
        LazyColumn(GlanceModifier.fillMaxWidth().defaultWeight()) {
            items(lines.size) { i -> LineView(lines[i], now) }
        }
    }
}

@Composable
private fun LineView(line: Line, now: LocalDateTime) {
    when (line) {
        is Line.Header -> Row(GlanceModifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            if (line.status != null) {
                Image(ImageProvider(line.status.icon()), null, GlanceModifier.size(16.dp), colorFilter = tint(line.status.color()))
                Spacer(GlanceModifier.width(6.dp))
            }
            PText(line.text, Face.COURSE, color = line.status?.color(), maxWidth = lineWidth() - 22.dp)
        }
        is Line.Note -> {
            val m = GlanceModifier.fillMaxWidth().padding(vertical = 6.dp)
            Box(if (line.key != null) m.clickable(open(line.key)) else m) {
                if (line.status != null) StatusLine(line.status, line.text, maxLines = 2) else PText(line.text, Face.BODY, maxLines = 3)
            }
        }
        is Line.Item -> when (val r = line.row) {
            is ClassRow -> {
                val l = r.slot.lesson
                RailRow(
                    start = l.start, end = l.end, timeColor = null,
                    node = if (r.current) Node.CURRENT else Node.RING, line = line,
                    onClick = open(TapKeys.schedule(r.slot.day)),
                ) {
                    if (r.current) PText(Words.classLabel(r.slot, now), Face.LABEL)
                    PText(l.subject, Face.COURSE, maxWidth = lineWidth() - 66.dp)
                    PText(Words.lessonMeta(l).ifEmpty { "Room not set" }, Face.BODY)
                    r.trouble?.let { StatusLine(it.status!!, Words.absenceWarning(it), maxLines = 2) }
                }
            }
            is DueRow -> {
                val d = r.deadline
                val color = r.status?.color()
                RailRow(
                    start = Fmt.clock(d.end), end = null, timeColor = color,
                    node = Node.Due(color), line = line,
                    onClick = open(TapKeys.deadline(d)),
                ) {
                    PText(Fmt.rowTitle(d.title), Face.ITEM, maxLines = 2)
                    if (r.status != null) {
                        StatusLine(r.status, Words.dueLine(r, now))
                        PText(courseName(d.courseName), Face.BODY)
                    } else {
                        PText(Words.dueLine(r, now), Face.BODY)
                    }
                }
            }
            is NoteRow -> RailRow(
                start = if (r.kind == NoteKind.FREE_AFTER) r.at?.let(Fmt::clock) else null, end = null, timeColor = null,
                node = Node.NONE, line = line, onClick = null,
            ) {
                PText(
                    when (r.kind) {
                        NoteKind.FREE_AFTER -> "Free for the rest of the day"
                        NoteKind.NO_MORE_CLASSES -> "No more classes today"
                        NoteKind.NO_CLASSES -> "No classes today"
                    },
                    Face.BODY,
                )
            }
        }
    }
}

private sealed interface Node {
    data object RING : Node
    data object CURRENT : Node
    data object NONE : Node
    data class Due(@ColorRes val color: Int?) : Node
}

/**
 * A rail row (DESIGN.md 5): the time column, the node column with the 2 dp line, and the
 * content. The line runs from the first node to the last.
 */
@Composable
private fun RailRow(
    start: String?,
    end: String?,
    @ColorRes timeColor: Int?,
    node: Node,
    line: Line.Item,
    onClick: Action?,
    content: @Composable ColumnScope.() -> Unit,
) {
    val m = GlanceModifier.fillMaxWidth()
    Row(if (onClick != null) m.clickable(onClick) else m) {
        Column(GlanceModifier.width(42.dp).padding(top = 6.dp), horizontalAlignment = Alignment.End) {
            if (start != null) PText(start, Face.NUMERAL, color = timeColor, maxWidth = 42.dp)
            if (end != null) PText(end, Face.NUMERAL_SMALL, maxWidth = 42.dp)
        }
        Box(GlanceModifier.width(24.dp).fillMaxHeight(), contentAlignment = Alignment.TopCenter) {
            Column(GlanceModifier.width(2.dp).fillMaxHeight()) {
                val rule = ColorProvider(R.color.w_rule)
                Box(GlanceModifier.width(2.dp).height(13.dp).let { if (line.lineAbove) it.background(rule) else it }) {}
                Box(GlanceModifier.width(2.dp).defaultWeight().let { if (line.lineBelow) it.background(rule) else it }) {}
            }
            when (node) {
                Node.RING -> {
                    NodeImage(R.drawable.w_node_dot, 12, R.color.w_paper, top = 7) // the line doesn't show through the ring
                    NodeImage(R.drawable.w_node_ring, 12, R.color.w_ink, top = 7)
                }
                Node.CURRENT -> NodeImage(R.drawable.w_node_dot, 12, R.color.w_primary, top = 7)
                is Node.Due -> NodeImage(R.drawable.w_node_dot, 8, node.color ?: R.color.w_ink, top = 9)
                Node.NONE -> {}
            }
        }
        Column(GlanceModifier.defaultWeight().padding(top = 6.dp, bottom = 6.dp), content = content)
    }
}

@Composable
private fun NodeImage(@DrawableRes res: Int, sizeDp: Int, @ColorRes color: Int, top: Int) {
    Box(GlanceModifier.padding(top = top.dp)) {
        Image(ImageProvider(res), null, GlanceModifier.size(sizeDp.dp), colorFilter = tint(color))
    }
}
