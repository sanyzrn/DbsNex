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
        for (id in ids) manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id)))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle?,
    ) {
        // The ring is drawn to the box, so a resize is a redraw with a new
        // number, not just the same ring re-centred.
        manager.updateAppWidget(id, views(context, newOptions))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_LOCALE_CHANGED) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, this::class.java)))
        }
    }

    private fun views(context: Context, options: Bundle?): RemoteViews {
        val display = NexWidgetAppearance.localized(context)
        val today = NexCycleToday.of(NexCycleSnapshot.read(context), LocalDate.now())
        val locked = today.phase == NexCycleToday.Phase.LOCKED
        val views = RemoteViews(context.packageName, R.layout.widget_cycle_discreet)
        // One cell is 40–57dp and the widget may be pulled to 200dp; the
        // ring follows whichever of the two axes is tighter, less its own
        // 6dp padding, so a stretched box is a bigger ring rather than the
        // same small one floating in it.
        val ringDp = NexCycleWidget.ringSizeDpSquare(
            options,
            fallback = RING_DP_DEFAULT,
            min = RING_DP_MIN,
            max = RING_DP_MAX,
            reserve = 12,
        )
        views.setImageViewBitmap(
            R.id.nex_cycle_discreet_ring,
            NexCycleWidget.ring(display, today, ringDp, if (locked) null else NexCycleWidget.center(display, today)),
        )
        views.setViewVisibility(R.id.nex_cycle_discreet_lock, if (locked) View.VISIBLE else View.GONE)
        views.setContentDescription(
            R.id.nex_cycle_discreet_root,
            display.getString(R.string.cycle_discreet_widget_a11y),
        )
        views.setOnClickPendingIntent(R.id.nex_cycle_discreet_root, NexWidgetActions.openCycle(context))
        return views
    }

    private companion object {
        /** The ring at a one-cell placement; the ceiling a stretched box grows it to. */
        const val RING_DP_DEFAULT = 72
        const val RING_DP_MIN = 48
        const val RING_DP_MAX = 176
    }
}
