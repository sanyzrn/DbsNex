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
 * The full Cycle widget: the ring, where you are ("12 days until your
 * period", "Period, day 2", "Week 12, day 2"), the line under it and a kind
 * word for the day — in Cycle's own blush and lavender.
 *
 * Reads [NexCycleSnapshot], never the database. Locked, it says to open Nex
 * and shows nothing else; with Cycle off it points to the profile. A tap
 * opens «Cycle» behind the app lock. Android wakes it every few hours
 * (`updatePeriodMillis`) so the day's count rolls over on its own.
 */
class CycleWidgetProvider : AppWidgetProvider() {

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
        val (title, headline, sub, whisper) = NexCycleWidget.lines(display, today)
        val views = RemoteViews(context.packageName, R.layout.widget_cycle)
        views.setInt(R.id.nex_cycle_root, "setLayoutDirection", display.resources.configuration.layoutDirection)
        views.setImageViewBitmap(R.id.nex_cycle_ring, NexCycleWidget.ring(display, today, 84, null))
        views.setTextViewText(R.id.nex_cycle_title, title)
        views.setTextViewText(R.id.nex_cycle_headline, headline)
        views.setTextViewText(R.id.nex_cycle_subline, sub)
        views.setViewVisibility(R.id.nex_cycle_subline, if (sub.isEmpty()) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.nex_cycle_whisper, whisper)
        views.setViewVisibility(R.id.nex_cycle_whisper, if (whisper.isEmpty()) View.GONE else View.VISIBLE)
        views.setViewVisibility(
            R.id.nex_cycle_lock,
            if (today.phase == NexCycleToday.Phase.LOCKED) View.VISIBLE else View.GONE,
        )
        views.setContentDescription(R.id.nex_cycle_root, "$title. $headline. $sub")
        views.setOnClickPendingIntent(R.id.nex_cycle_root, NexWidgetActions.openCycle(context))
        return views
    }
}
