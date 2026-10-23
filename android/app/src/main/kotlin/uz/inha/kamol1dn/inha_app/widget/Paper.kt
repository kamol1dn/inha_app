package uz.inha.kamol1dn.inha_app.widget

import android.content.Context
import android.os.Build
import android.widget.RemoteViews
import androidx.annotation.ColorRes
import androidx.annotation.DrawableRes
import androidx.annotation.LayoutRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.unit.ColorProvider
import es.antonborri.home_widget.actionStartActivity
import uz.inha.kamol1dn.inha_app.MainActivity
import uz.inha.kamol1dn.inha_app.R
import uz.inha.kamol1dn.inha_app.campus.AbsenceState
import uz.inha.kamol1dn.inha_app.campus.Status
import uz.inha.kamol1dn.inha_app.campus.TapKeys

// Campus paper for widgets (DESIGN.md): paper and ink, Fraunces for the answers, Public Sans for
// the rest, thin rules, status as icon plus words, and the tally. Colours are resources with a
// night variant, so the launcher picks light or dark with the system.

@ColorRes
fun Status.color(): Int = when (this) {
    Status.OK -> R.color.w_ok
    Status.WARNING -> R.color.w_warning
    Status.DANGER -> R.color.w_danger
    Status.INFO -> R.color.w_primary
}

@DrawableRes
fun Status.icon(): Int = when (this) {
    Status.OK -> R.drawable.w_ic_ok
    Status.WARNING -> R.drawable.w_ic_warning
    Status.DANGER -> R.drawable.w_ic_danger
    Status.INFO -> R.drawable.w_ic_info
}

/** The text styles of DESIGN.md 4, scaled for a widget. Each is a layout with one TextView. */
enum class Face(@LayoutRes val layout: Int) {
    ROOM(R.layout.w_text_room),
    HEADLINE(R.layout.w_text_headline),
    COURSE_ITALIC(R.layout.w_text_course_italic),
    COURSE(R.layout.w_text_course),
    ITEM(R.layout.w_text_item),
    BODY(R.layout.w_text_body),
    LABEL(R.layout.w_text_label),
    NUMERAL(R.layout.w_text_numeral),
    NUMERAL_SMALL(R.layout.w_text_numeral_small),
    SMALL(R.layout.w_text_small),
}

/**
 * Text in one of the app's faces. Glance's own Text can only use system fonts, so this is a
 * plain TextView from an XML layout: real text, read by TalkBack, sized in sp.
 */
@Composable
fun PText(
    text: String,
    face: Face,
    modifier: GlanceModifier = GlanceModifier,
    @ColorRes color: Int? = null,
    maxLines: Int = 1,
) {
    val context = LocalContext.current
    val rv = RemoteViews(context.packageName, face.layout).apply {
        setTextViewText(R.id.w_text, text)
        if (maxLines != 1) setInt(R.id.w_text, "setMaxLines", maxLines)
        if (color != null) setTextColorRes(context, color)
    }
    AndroidRemoteViews(rv, modifier)
}

private fun RemoteViews.setTextColorRes(context: Context, @ColorRes color: Int) {
    if (Build.VERSION.SDK_INT >= 31) {
        setColor(R.id.w_text, "setTextColor", color) // resolved by the launcher, day or night
    } else {
        setTextColor(R.id.w_text, ContextCompat.getColor(context, color))
    }
}

fun tint(@ColorRes color: Int) = ColorFilter.tint(ColorProvider(color))

/** A 14 dp status icon and the words, both in the status colour (DESIGN.md 3). */
@Composable
fun StatusLine(status: Status, text: String, modifier: GlanceModifier = GlanceModifier, maxLines: Int = 1) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        Image(
            ImageProvider(status.icon()),
            contentDescription = null,
            modifier = GlanceModifier.size(14.dp).padding(top = 1.dp),
            colorFilter = tint(status.color()),
        )
        Spacer(GlanceModifier.width(6.dp))
        PText(text, Face.BODY, color = status.color(), maxLines = maxLines)
    }
}

/** "as of Tue 18:04" after a stale source, in warning (DESIGN.md 7). */
@Composable
fun StaleMarker(text: String, modifier: GlanceModifier = GlanceModifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Image(
            ImageProvider(R.drawable.w_ic_sync_problem),
            contentDescription = null,
            modifier = GlanceModifier.size(12.dp),
            colorFilter = tint(R.color.w_warning),
        )
        Spacer(GlanceModifier.width(4.dp))
        PText(text, Face.SMALL, color = R.color.w_warning)
    }
}

/** A thin rule in outlineVariant. */
@Composable
fun Rule(modifier: GlanceModifier = GlanceModifier) {
    Box(modifier.fillMaxWidth().height(1.dp).background(ColorProvider(R.color.w_rule))) {}
}

/** Opens the app on what [key] names (see TapKeys). */
@Composable
fun open(key: String): Action = actionStartActivity<MainActivity>(LocalContext.current, TapKeys.uri(key))

/** The widget's paper, with the system's widget corner radius; tapping it opens [key]. */
@Composable
fun PaperFrame(key: String, content: @Composable ColumnScope.() -> Unit) {
    var m = GlanceModifier.fillMaxSize().appWidgetBackground().background(ColorProvider(R.color.w_paper))
    if (Build.VERSION.SDK_INT >= 31) m = m.cornerRadius(android.R.dimen.system_app_widget_background_radius)
    Column(m.clickable(open(key)).padding(horizontal = 16.dp, vertical = 12.dp), content = content)
}

/**
 * Absences as tally marks: one stroke per absence in gates of five, used strokes in ink (or the
 * status colour), the ones still allowed faint (DESIGN.md 8). Nothing past 20 marks; the count
 * beside it carries the number either way.
 */
@Composable
fun Tally(state: AbsenceState) {
    val total = maxOf(state.used, state.limit ?: 0)
    if (total == 0 || total > 20) return
    val over = state.limit != null && state.used > state.limit
    val used = state.status?.let { if (over) Status.DANGER.color() else it.color() } ?: R.color.w_ink
    fun colorOf(i: Int) = if (i < state.used) used else R.color.w_rule
    Row {
        for (gate in 0 until (total + 4) / 5) {
            val first = gate * 5
            val marks = minOf(5, total - first)
            if (gate > 0) Spacer(GlanceModifier.width(10.dp))
            Box {
                // The faint diagonal goes under inked uprights, an inked one over them.
                val slash = marks == 5
                val slashUsed = slash && first + 4 < state.used
                if (slash && !slashUsed) Slash(colorOf(first + 4))
                Row {
                    for (i in 0 until minOf(4, marks)) {
                        if (i > 0) Spacer(GlanceModifier.width(5.dp))
                        Box(GlanceModifier.width(2.dp).height(16.dp).background(ColorProvider(colorOf(first + i)))) {}
                    }
                }
                if (slashUsed) Slash(colorOf(first + 4))
            }
        }
    }
}

@Composable
private fun Slash(@ColorRes color: Int) {
    Image(
        ImageProvider(R.drawable.w_tally_slash),
        contentDescription = null,
        modifier = GlanceModifier.width(23.dp).height(16.dp),
        colorFilter = tint(color),
    )
}
