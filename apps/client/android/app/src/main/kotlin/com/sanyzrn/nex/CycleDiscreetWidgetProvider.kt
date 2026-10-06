package com.sanyzrn.nex

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import java.time.LocalDate

/**
 * The discreet Cycle widget: the ring and one number in it — days until
 * the period, or the day of it — and not one word. Someone glancing at the
 * phone sees a ring; the person it belongs to knows what it counts.
 *
 * Its accessibility label is "Nex" for the same reason. Locked, it shows a
 * small lock and no ring. A tap opens «Cycle» behind the app lock.
 */
class CycleDiscreetWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle?,
    ) {
        manager.updateAppWidget(id, views(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_LOCALE_CHANGED) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, this::class.java)))
        }
    }

    private fun views(context: Context): RemoteViews {
        val display = NexWidgetAppearance.localized(context)
        val today = NexCycleToday.of(NexCycleSnapshot.read(context), LocalDate.now())
        val locked = today.phase == NexCycleToday.Phase.LOCKED
        val views = RemoteViews(context.packageName, R.layout.widget_cycle_discreet)
        views.setImageViewBitmap(
            R.id.nex_cycle_discreet_ring,
            NexCycleWidget.ring(display, today, 72, if (locked) null else NexCycleWidget.center(display, today)),
        )
        views.setViewVisibility(R.id.nex_cycle_discreet_lock, if (locked) View.VISIBLE else View.GONE)
        views.setContentDescription(
            R.id.nex_cycle_discreet_root,
            display.getString(R.string.cycle_discreet_widget_a11y),
        )
        views.setOnClickPendingIntent(R.id.nex_cycle_discreet_root, NexWidgetActions.openCycle(context))
        return views
    }
}
