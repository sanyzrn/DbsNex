package com.sanyzrn.nex

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Lines of the Recap widget's brief, one row each.
 *
 * A list rather than one TextView so a brief longer than the widget scrolls
 * instead of being cut off — RemoteViews offer no scrolling container but a
 * collection. Like [TimelineWidgetService], the factory re-reads the
 * snapshot on every data-set change, so the rows can never be fresher or
 * staler than the frame the provider rendered from.
 */
class RecapWidgetService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext)

    companion object {
        fun intent(context: Context): Intent =
            Intent(context, RecapWidgetService::class.java)
    }

    private class Factory(private val context: Context) : RemoteViewsFactory {

        private var lines: List<String> = emptyList()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            val snapshot = NexWidgetSnapshot.read(context)
            lines = if (snapshot == null || snapshot.appLock) {
                emptyList()
            } else {
                snapshot.recap.orEmpty().lines().map { it.trimEnd() }.filter { it.isNotBlank() }
            }
        }

        override fun onDestroy() {
            lines = emptyList()
        }

        override fun getCount(): Int = lines.size

        override fun getViewAt(position: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_recap_row)
            views.setTextViewText(R.id.nex_recap_row, lines[position])
            // A tap on a line opens the app, as a tap anywhere else on the
            // widget does; the template is set by the provider.
            views.setOnClickFillInIntent(R.id.nex_recap_row, Intent())
            return views
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = position.toLong()

        override fun hasStableIds(): Boolean = false
    }
}
