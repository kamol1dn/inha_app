package uz.inha.kamol1dn.inha_app.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.LocalState
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.width
import androidx.glance.unit.ColorProvider
import java.time.LocalDateTime
import uz.inha.kamol1dn.inha_app.R
import uz.inha.kamol1dn.inha_app.campus.Campus
import uz.inha.kamol1dn.inha_app.campus.Fmt
import uz.inha.kamol1dn.inha_app.campus.Status
import uz.inha.kamol1dn.inha_app.campus.TapKeys
import uz.inha.kamol1dn.inha_app.campus.UpNext
import uz.inha.kamol1dn.inha_app.campus.Words
import uz.inha.kamol1dn.inha_app.campus.courseName
import uz.inha.kamol1dn.inha_app.campus.deadlineStatus
import uz.inha.kamol1dn.inha_app.campus.eclassMissing
import uz.inha.kamol1dn.inha_app.campus.eclassStaleAfter
import uz.inha.kamol1dn.inha_app.campus.staleNote
import uz.inha.kamol1dn.inha_app.campus.timetableStaleAfter
import uz.inha.kamol1dn.inha_app.campus.upNext
import uz.inha.kamol1dn.inha_app.campus.vodFor

/**
 * "Up next": the class in progress or the next one (room, time, countdown) and the next thing
 * due. Small, it is the room and one line for what is due; wide, the two side by side; tall,
 * everything with the time, kind and attendance warning.
 */
class UpNextWidget : GlanceAppWidget() {
    // Exact: the layout and every Fraunces line's width budget come from the real size.
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            LocalState.current // read so that every update() recomposes and the cache is read again
            UpNextContent(Campus.read(context), LocalDateTime.now())
        }
    }
}

class UpNextWidgetReceiver : PaperWidgetReceiver() {
    override val glanceAppWidget = UpNextWidget()
}

@Composable
fun UpNextContent(c: Campus, now: LocalDateTime) {
    val size = LocalSize.current
    val u = upNext(c.lessons?.value.orEmpty(), c.deadlines?.value.orEmpty(), c.attendance?.value.orEmpty(), c.limits, now)
    PaperFrame(TapKeys.tab(0)) {
        if (size.height < 170.dp && size.width >= 240.dp) {
            Row(GlanceModifier.fillMaxSize()) {
                val half = (lineWidth() - 25.dp) / 2
                ClassBlock(c, u, now, detail = false, textWidth = half, modifier = GlanceModifier.defaultWeight().fillMaxHeight())
                Spacer(GlanceModifier.width(12.dp))
                Box(GlanceModifier.width(1.dp).fillMaxHeight().background(ColorProvider(R.color.w_rule))) {}
                Spacer(GlanceModifier.width(12.dp))
                DueBlock(c, u, now, compact = false, modifier = GlanceModifier.defaultWeight().fillMaxHeight())
            }
        } else {
            val tall = size.height >= 170.dp
            ClassBlock(c, u, now, detail = tall, textWidth = lineWidth(), modifier = GlanceModifier.fillMaxWidth())
            Spacer(GlanceModifier.defaultWeight())
            Rule()
            Spacer(GlanceModifier.height(6.dp))
            DueBlock(c, u, now, compact = !tall, modifier = GlanceModifier.fillMaxWidth())
        }
    }
}

@Composable
private fun ClassBlock(c: Campus, u: UpNext, now: LocalDateTime, detail: Boolean, textWidth: Dp, modifier: GlanceModifier) {
    val slot = u.slot
    val m = if (slot != null) modifier.clickable(open(TapKeys.schedule(slot.day))) else modifier
    Column(m) {
        when {
            c.lessons == null -> PText("Open the app to load the timetable.", Face.BODY, maxLines = 3)
            slot == null -> PText("No classes in the next 7 days.", Face.BODY, maxLines = 2)
            else -> {
                val l = slot.lesson
                PText(Words.classLabel(slot, now), Face.LABEL)
                if (l.room.isEmpty()) {
                    PText("Room not set", Face.COURSE, color = R.color.w_muted, maxWidth = textWidth)
                } else {
                    PText(l.room, Face.ROOM, maxWidth = textWidth)
                }
                PText(l.subject, Face.COURSE_ITALIC, maxWidth = textWidth)
                if (detail) {
                    Spacer(GlanceModifier.height(2.dp))
                    PText(listOf(Fmt.range(slot.start, slot.end), l.kind, l.teacher).filter { it.isNotEmpty() }.joinToString(" · "), Face.BODY)
                    u.trouble?.let { StatusLine(it.status!!, Words.absenceWarning(it), maxLines = 2) }
                }
            }
        }
        if (detail) staleNote("Timetable", c.lessons, now, timetableStaleAfter)?.let { StaleMarker(it) }
    }
}

@Composable
private fun DueBlock(c: Campus, u: UpNext, now: LocalDateTime, compact: Boolean, modifier: GlanceModifier) {
    val due = u.due
    val m = if (due != null) modifier.clickable(open(TapKeys.deadline(due))) else modifier
    Column(m) {
        when {
            c.deadlines == null -> PText(eclassMissing(c.eclassAccount, "deadlines"), Face.BODY, maxLines = 3)
            due == null -> StatusLine(Status.OK, "Nothing due in eClass.")
            else -> {
                val status = deadlineStatus(due, now)
                val line = Words.dueWhen(due, vodFor(due, c.attendance?.value.orEmpty()), now)
                PText(Fmt.rowTitle(due.title), Face.ITEM, maxLines = if (compact) 1 else 2)
                val lines = if (compact) 1 else 2
                if (status != null) StatusLine(status, line, maxLines = lines) else PText(line, Face.BODY, maxLines = lines)
                if (!compact) PText(courseName(due.courseName), Face.BODY)
            }
        }
        if (!compact) {
            if (c.eclassAccount?.ok == false && c.deadlines != null) {
                StatusLine(Status.DANGER, "eClass sign-in needed.")
            } else {
                staleNote("eClass", c.deadlines, now, eclassStaleAfter)?.let { StaleMarker(it) }
            }
        }
    }
}
