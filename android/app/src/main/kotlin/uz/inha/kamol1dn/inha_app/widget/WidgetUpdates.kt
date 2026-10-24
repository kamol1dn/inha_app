package uz.inha.kamol1dn.inha_app.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.updateAll
import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import uz.inha.kamol1dn.inha_app.campus.Campus
import uz.inha.kamol1dn.inha_app.campus.nextTick

/**
 * The widgets' receivers. An update comes from the app after every cache write (home_widget's
 * `updateWidget`, which sends APPWIDGET_UPDATE here), from the system every 30 minutes, and from
 * [WidgetTicker] when something on the widgets changes with the clock.
 */
abstract class PaperWidgetReceiver : GlanceAppWidgetReceiver() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetTicker.schedule(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetTicker.schedule(context) // cancels the alarm once no widget is left
    }
}

/**
 * Re-renders the widgets when the clock changes what they say: a class starts or ends, a
 * countdown moves on, an item turns urgent, the day changes. The alarm is inexact and doesn't
 * wake the phone (RTC), so it costs nothing while the screen is off and fires on the next wake.
 */
object WidgetTicker {
    private val receivers = listOf(
        UpNextWidgetReceiver::class.java,
        TodayWidgetReceiver::class.java,
        AttendanceWidgetReceiver::class.java,
    )

    private fun anyPlaced(context: Context): Boolean {
        val manager = AppWidgetManager.getInstance(context)
        return receivers.any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    private fun pending(context: Context) = PendingIntent.getBroadcast(
        context, 0, Intent(context, WidgetTickReceiver::class.java),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        if (!anyPlaced(context)) {
            alarms.cancel(pending(context))
            return
        }
        val c = Campus.read(context)
        val zone = ZoneId.systemDefault()
        val at = nextTick(
            c.lessons?.value.orEmpty(), c.deadlines?.value.orEmpty(), c.attendance?.value.orEmpty(), LocalDateTime.now(),
            c.classFree,
        )
        alarms.set(AlarmManager.RTC, at.atZone(zone).toInstant().toEpochMilli(), pending(context))
    }

    suspend fun updateAll(context: Context) {
        UpNextWidget().updateAll(context)
        TodayWidget().updateAll(context)
        AttendanceWidget().updateAll(context)
        schedule(context)
    }
}

class WidgetTickReceiver : BroadcastReceiver() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onReceive(context: Context, intent: Intent) {
        val done = goAsync()
        scope.launch {
            try {
                WidgetTicker.updateAll(context.applicationContext)
            } finally {
                done.finish()
            }
        }
    }
}
