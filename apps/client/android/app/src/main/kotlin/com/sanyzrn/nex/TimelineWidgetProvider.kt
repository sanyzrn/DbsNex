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
 * The Timeline widget: the top of the timeline before the app is open, with
 * the capture button always in reach.
 *
 * Nex is a timeline, not a folder tree — one reverse-chronological stream is
 * the product's whole organization story. The widget shows exactly that: the
 * first rows of the stream, in the order the app puts them in (pinned first,
 * then most recently touched), each row the same 48dp height with a type
 * glyph, a one-line preview and a relative time — the same anatomy, buckets
 * and vocabulary as an in-app card, compressed to a glance.
 *
 * Everything it knows comes from the snapshot file Dart writes
 * ([NexWidgetSnapshot]); the widget never touches SQLite, and the file is
 * the only surface where privacy has to hold. Three states, checked in this
 * order:
 *
 *  - **Locked** — the app lock is on. The list is never bound, the header
 *    keeps its capture button (capture happens inside the app, behind the
 *    lock gate), and the body says the library is locked. Note content is
 *    not merely hidden here: the snapshot carries none when the lock is on,
 *    so there is nothing on disk the home screen could render.
 *  - **Empty** — no notes yet, or no snapshot yet (the app has never run, or
 *    its file is unreadable). A quiet prompt toward capture, the widget-side
 *    echo of the timeline's own empty state; a missing snapshot is an
 *    absence, not an error, and says nothing scary about it.
 *  - **Content** — the list, bound to [TimelineWidgetService], one
 *    PendingIntent template for every row, filled in per row with the note's
 *    id.
 */
class TimelineWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, views(context, manager, id))
        }
        // One call for the batch: the launcher rebinds the list service, and
        // the factory re-reads the snapshot — rows can never out-fresh the
        // frame the provider just pushed.
        manager.notifyAppWidgetViewDataChanged(ids, R.id.nex_widget_list)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle?,
    ) {
        // The ListView scrolls whatever height the launcher grants; rows do
        // not reflow with size. Re-rendering keeps the header's paddings and
        // the rest of the frame honest after a resize all the same.
        manager.updateAppWidget(id, views(context, manager, id))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == Intent.ACTION_LOCALE_CHANGED) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(ComponentName(context, this::class.java))
            onUpdate(context, manager, ids)
        }
    }

    private fun views(context: Context, manager: AppWidgetManager, id: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_timeline)
        val snapshot = NexWidgetSnapshot.read(context)

        // The header is common to every state: brand on one side, capture on
        // the other. Both survive the lock — the brand opens the app (which
        // gates itself), and capture never touches note content.
        views.setOnClickPendingIntent(
            R.id.nex_widget_header,
            NexWidgetActions.openApp(context),
        )
        views.setOnClickPendingIntent(
            R.id.nex_widget_capture_badge,
            NexWidgetActions.textCapture(context),
        )
        views.setContentDescription(
            R.id.nex_widget_capture_badge,
            context.getString(R.string.widget_a11y_capture),
        )
        // The body is one tap away from the timeline from any state.
        views.setOnClickPendingIntent(
            R.id.nex_widget_timeline_root,
            NexWidgetActions.openApp(context),
        )

        when {
            snapshot?.appLock == true -> {
                views.setViewVisibility(R.id.nex_widget_list, View.GONE)
                views.setViewVisibility(R.id.nex_widget_empty, View.GONE)
                views.setViewVisibility(R.id.nex_widget_locked, View.VISIBLE)
                views.setTextViewText(
                    R.id.nex_widget_locked_text,
                    context.getString(R.string.widget_locked_title),
                )
                views.setContentDescription(
                    R.id.nex_widget_locked,
                    context.getString(R.string.widget_locked_a11y),
                )
            }
            snapshot == null || snapshot.notes.isEmpty() -> {
                views.setViewVisibility(R.id.nex_widget_list, View.GONE)
                views.setViewVisibility(R.id.nex_widget_locked, View.GONE)
                views.setViewVisibility(R.id.nex_widget_empty, View.VISIBLE)
                views.setTextViewText(
                    R.id.nex_widget_empty_title,
                    context.getString(R.string.widget_empty_title),
                )
                views.setTextViewText(
                    R.id.nex_widget_empty_hint,
                    context.getString(R.string.widget_empty_hint),
                )
            }
            else -> {
                views.setViewVisibility(R.id.nex_widget_locked, View.GONE)
                views.setViewVisibility(R.id.nex_widget_empty, View.GONE)
                views.setViewVisibility(R.id.nex_widget_list, View.VISIBLE)
                views.setRemoteAdapter(
                    R.id.nex_widget_list,
                    TimelineWidgetService.intent(context),
                )
                views.setPendingIntentTemplate(
                    R.id.nex_widget_list,
                    NexWidgetActions.openNoteTemplate(context),
                )
            }
        }
        return views
    }
}
