package com.sanyzrn.nex

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/**
 * Rows for the Timeline widget's list.
 *
 * The service runs in this app's process; the launcher binds it (the system
 * mediates, under `BIND_REMOTEVIEWS`) and asks the factory for views. The
 * factory re-reads the snapshot file on every data-set change, so a row can
 * never be fresher or staler than the file the provider rendered from —
 * there is one source, and both halves read it at push time.
 *
 * A row is the note, compressed to what a glance takes: the type's glyph
 * (the same mapping the timeline cards use), the preview text Dart already
 * cut to size, or — when the note has no text of its own, like a photo
 * nobody captioned — the type's name in the widget's language, which is what
 * the timeline card does in the same situation. The relative time is the
 * same bucket set the app shows, formatted here so it ages honestly between
 * pushes instead of freezing at whatever the snapshot said.
 */
class TimelineWidgetService : RemoteViewsService() {

    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Factory(applicationContext)

    companion object {
        fun intent(context: Context): Intent =
            Intent(context, TimelineWidgetService::class.java)
    }

    private class Factory(private val context: Context) : RemoteViewsFactory {

        private var notes: List<NexWidgetSnapshot.NexWidgetNote> = emptyList()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            // Read fresh, every time. The factory is recreated by the
            // launcher whenever the widget's data set is notified; between
            // those moments the list is static, which is exactly the deal a
            // home-screen glance offers.
            val snapshot = NexWidgetSnapshot.read(context)
            notes = if (snapshot == null || snapshot.appLock) emptyList() else snapshot.notes
        }

        override fun onDestroy() {
            notes = emptyList()
        }

        override fun getCount(): Int = notes.size

        override fun getViewAt(position: Int): RemoteViews {
            val note = notes[position]
            val views = RemoteViews(context.packageName, R.layout.widget_timeline_row)
            views.setImageViewResource(R.id.nex_widget_row_icon, iconFor(note.type))
            val preview = note.preview.trim()
            // A row with no text of its own speaks its type's name, the way
            // the timeline card does — and the row reads as one coherent
            // line ("the note, two minutes ago"), which is what the design
            // doc asks of a card read-out.
            val spoken = if (preview.isEmpty()) typeLabel(note.type) else preview
            views.setTextViewText(R.id.nex_widget_row_preview, spoken)
            val time = NexWidgetTime.label(context, note.updatedAt, System.currentTimeMillis())
            views.setTextViewText(R.id.nex_widget_row_time, time)
            views.setContentDescription(R.id.nex_widget_row_root, "$spoken, $time")
            // The note id rides the template's fill-in intent, and the
            // template is immutable to everyone but the launcher that fills
            // it in — the row itself carries nothing secret.
            val fillIn = Intent().putExtra(NexWidgetActions.EXTRA_NOTE_ID, note.id)
            views.setOnClickFillInIntent(R.id.nex_widget_row_root, fillIn)
            return views
        }

        override fun getLoadingView(): RemoteViews =
            RemoteViews(context.packageName, R.layout.widget_timeline_loading)

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long =
            notes[position].id.hashCode().toLong()

        override fun hasStableIds(): Boolean = true

        private fun iconFor(type: String): Int = when (type) {
            "voice" -> R.drawable.nex_widget_ic_type_voice
            "photo" -> R.drawable.nex_widget_ic_type_photo
            "file" -> R.drawable.nex_widget_ic_type_file
            "checklist" -> R.drawable.nex_widget_ic_type_checklist
            "link" -> R.drawable.nex_widget_ic_type_link
            // The timeline's catch-all is an infinity glyph; the widget keeps
            // that mapping so an unfamiliar type never pretends to be text.
            "text" -> R.drawable.nex_widget_ic_type_text
            else -> R.drawable.nex_widget_ic_type_other
        }

        private fun typeLabel(type: String): String = context.getString(
            when (type) {
                "voice" -> R.string.widget_type_voice
                "photo" -> R.string.widget_type_photo
                "file" -> R.string.widget_type_file
                "checklist" -> R.string.widget_type_checklist
                "link" -> R.string.widget_type_link
                else -> R.string.widget_type_text
            }
        )
    }
}
