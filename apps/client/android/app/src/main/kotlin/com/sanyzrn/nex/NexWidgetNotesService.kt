package com.sanyzrn.nex

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Feeds the recent-notes widget's list. Each row is one note from the
 * snapshot file, themed the same way the rest of the widgets are, with a tap
 * that opens the note in the app.
 */
class NexWidgetNotesService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        NexWidgetNotesFactory(
            applicationContext,
            intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 0),
        )
}

class NexWidgetNotesFactory(
    private val context: Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private var notes: List<WidgetNote> = emptyList()

    override fun onCreate() {}
    override fun onDestroy() {}

    override fun onDataSetChanged() {
        // Runs on the service's own thread; the snapshot is a small JSON
        // file, so reading it fresh on every data change is cheap.
        notes = WidgetSnapshot.read(context)
    }

    override fun getCount(): Int = if (notes.isEmpty()) 1 else notes.size

    override fun getViewAt(position: Int): RemoteViews {
        if (notes.isEmpty()) return emptyViews()
        val note = notes[position]
        val t = widgetTheme(context)

        val views = RemoteViews(context.packageName, R.layout.widget_notes_row)
        views.setImageViewResource(R.id.row_disc_bg, t.discNeutral)
        views.setInt(R.id.row_type_icon, "setColorFilter", t.iconTint)
        views.setImageViewResource(R.id.row_type_icon, widgetIconFor(note.type))
        views.setTextViewText(
            R.id.row_text,
            note.text.ifBlank { context.getString(R.string.widget_open_note) },
        )
        views.setTextColor(R.id.row_text, t.text)
        views.setTextViewText(R.id.row_time, relativeTime(note.timestampMillis))
        views.setTextColor(R.id.row_time, t.secondary)

        if (note.pinned) {
            views.setViewVisibility(R.id.row_pin, android.view.View.VISIBLE)
            views.setInt(R.id.row_pin, "setColorFilter", t.accent)
        } else {
            views.setViewVisibility(R.id.row_pin, android.view.View.GONE)
        }

        // A distinct request code per row (and per widget instance), so the
        // launcher keeps one PendingIntent per note rather than collapsing
        // them all onto the first.
        views.setOnClickPendingIntent(
            R.id.note_row,
            NexWidgetProvider.launchPending(
                context,
                MainActivity.ACTION_OPEN_NOTE,
                noteId = note.id,
                requestCode = appWidgetId * 100 + position + 1,
            ),
        )
        return views
    }

    private fun emptyViews(): RemoteViews {
        val t = widgetTheme(context)
        val views = RemoteViews(context.packageName, R.layout.widget_notes_empty)
        views.setTextViewText(R.id.empty_title, context.getString(R.string.widget_empty_title))
        views.setTextViewText(R.id.empty_hint, context.getString(R.string.widget_empty_hint))
        views.setTextColor(R.id.empty_title, t.text)
        views.setTextColor(R.id.empty_hint, t.secondary)
        views.setOnClickPendingIntent(
            R.id.notes_empty_root,
            NexWidgetProvider.launchPending(context, MainActivity.ACTION_TEXT_CAPTURE),
        )
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true

    /** "now", "5 mins ago", "yesterday"… then a short date. */
    private fun relativeTime(millis: Long): String {
        if (millis <= 0) return ""
        val minutes = (System.currentTimeMillis() - millis) / 60_000L
        return when {
            minutes < 1 -> context.getString(R.string.widget_time_now)
            minutes < 60 ->
                context.getQuantityString(
                    R.plurals.widget_time_minutes,
                    minutes.toInt(),
                    minutes.toInt(),
                )
            minutes < 60 * 24 ->
                context.getQuantityString(
                    R.plurals.widget_time_hours,
                    (minutes / 60).toInt(),
                    (minutes / 60).toInt(),
                )
            minutes < 60 * 24 * 7 ->
                context.getQuantityString(
                    R.plurals.widget_time_days,
                    (minutes / (60 * 24)).toInt(),
                    (minutes / (60 * 24)).toInt(),
                )
            else -> SimpleDateFormat("MMM d", Locale.getDefault()).format(Date(millis))
        }
    }
}
