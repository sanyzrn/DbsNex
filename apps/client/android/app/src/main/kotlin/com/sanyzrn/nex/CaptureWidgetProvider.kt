package com.sanyzrn.nex

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews

/**
 * The Capture widget: Nex's capture reflex on the home screen (FR-8.1,
 * ADR-027). One accent tile, one action — a tap opens Nex straight into text
 * capture, the same sheet the timeline's own button opens, with zero fields
 * to fill before typing.
 *
 * There is deliberately no data in this widget and therefore no snapshot, no
 * update channel and no privacy state to manage: a capture is typed inside
 * the app, behind the app-lock gate when that is on, so the tile renders
 * identically whether the library is locked, empty or full. Everything about
 * it that can change — the label's language, the theme, the wallpaper-derived
 * colors — is resolved from resources at render time.
 *
 * One tile, two shapes. Android 12's widget picker sizes widgets in cells and
 * older launchers resize in raw dp; both end up here either way, in
 * `onUpdate` or in `onAppWidgetOptionsChanged`. At one cell wide the tile is
 * the glyph alone, mirroring the timeline's capture button; stretched to two
 * cells or more it grows the "Capture" label, so the wide shape still reads
 * as a verb and not as a brand block. The break sits at 100dp: one cell is
 * 40–57dp of usable width on every grid this app can be placed on, and two
 * cells never come back under 110dp.
 */
class CaptureWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, views(context, manager, id))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle?,
    ) {
        manager.updateAppWidget(id, views(context, manager, id))
    }

    /**
     * A locale change re-renders every running widget with the new strings —
     * RemoteViews carry the *rendered* text, not the resource reference, so
     * nothing else would pick up `values-fa` on a device that switched.
     */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_LOCALE_CHANGED) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, this::class.java))
            onUpdate(context, manager, ids)
        }
    }

    private fun views(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val options = manager.getAppWidgetOptions(id)
        val wide = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) >= WIDE_AT_DP
        val views = RemoteViews(context.packageName, R.layout.capture_widget)
        views.setTextViewText(
            R.id.nex_widget_capture_label,
            context.getString(R.string.widget_capture_label),
        )
        views.setViewVisibility(
            R.id.nex_widget_capture_label,
            if (wide) View.VISIBLE else View.GONE,
        )
        views.setOnClickPendingIntent(
            R.id.nex_widget_capture_root,
            NexWidgetActions.textCapture(context),
        )
        views.setContentDescription(
            R.id.nex_widget_capture_root,
            context.getString(R.string.widget_a11y_capture),
        )
        return views
    }

    private companion object {
        /** From here up the tile shows its label (two cells on any grid). */
        const val WIDE_AT_DP = 100
    }
}
