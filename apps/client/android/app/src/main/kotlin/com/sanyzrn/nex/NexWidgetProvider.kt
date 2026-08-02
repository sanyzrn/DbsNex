package com.sanyzrn.nex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.widget.RemoteViews

/**
 * The four home-screen widgets, one provider class each so the launcher's
 * widget picker shows four distinct entries without any configuration step.
 *
 * The design follows the app's own tokens (nex_tokens.dart): a rounded card,
 * a neutral or accent disc, the ink-blue accent, and quiet secondary text —
 * with light and dark variants picked from the device's night mode. The
 * Flutter side keeps `widget_snapshot.json` fresh after every timeline
 * refresh and pokes this provider through the `nex/widgets` channel.
 */
abstract class NexWidgetProvider : AppWidgetProvider() {
    /** Which widget this class is; the four classes differ only in this. */
    abstract val widgetType: String

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) update(context, manager, id, widgetType)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) refreshAll(context)
    }

    companion object {
        const val TYPE_QUICK_CAPTURE = "quick_capture"
        const val TYPE_VOICE = "voice"
        const val TYPE_CAMERA = "camera"
        const val TYPE_NOTES = "notes"

        const val ACTION_REFRESH = "com.sanyzrn.nex.WIDGET_REFRESH"

        private val widgetClasses = listOf(
            NexQuickCaptureWidget::class.java,
            NexVoiceWidget::class.java,
            NexCameraWidget::class.java,
            NexNotesWidget::class.java,
        )

        /** Repaints every placed widget of every type from the latest snapshot. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            for (cls in widgetClasses) {
                val type = when (cls) {
                    NexQuickCaptureWidget::class.java -> TYPE_QUICK_CAPTURE
                    NexVoiceWidget::class.java -> TYPE_VOICE
                    NexCameraWidget::class.java -> TYPE_CAMERA
                    else -> TYPE_NOTES
                }
                val ids = manager.getAppWidgetIds(ComponentName(context, cls))
                for (id in ids) update(context, manager, id, type)
            }
        }

        fun update(
            context: Context,
            manager: AppWidgetManager,
            id: Int,
            type: String,
        ) {
            val views = if (type == TYPE_NOTES) {
                notesViews(context, id)
            } else {
                actionViews(context, type)
            }
            manager.updateAppWidget(id, views)
            if (type == TYPE_NOTES) {
                // The list's adapter reads the snapshot file; this is what
                // makes it re-read after a capture, edit or delete.
                manager.notifyAppWidgetViewDataChanged(intArrayOf(id), R.id.notes_list)
            }
        }

        /* ------------------------------------------------------------ views */

        private fun actionViews(context: Context, type: String): RemoteViews {
            val t = widgetTheme(context)
            val views = RemoteViews(context.packageName, R.layout.widget_action)
            views.setInt(R.id.widget_root, "setBackgroundResource", t.cardBackground)
            views.setTextColor(R.id.widget_title, t.text)
            views.setTextColor(R.id.widget_subtitle, t.secondary)
            views.setImageViewResource(R.id.widget_disc_bg, t.discAccent)
            views.setInt(R.id.widget_disc_icon, "setColorFilter", t.onAccent)

            val (icon, title, subtitle, action) = when (type) {
                TYPE_VOICE -> ActionSpec(
                    R.drawable.ic_widget_mic,
                    R.string.widget_voice_title,
                    R.string.widget_voice_subtitle,
                    MainActivity.ACTION_VOICE_CAPTURE,
                )
                TYPE_CAMERA -> ActionSpec(
                    R.drawable.ic_widget_camera,
                    R.string.widget_camera_title,
                    R.string.widget_camera_subtitle,
                    MainActivity.ACTION_PHOTO_CAPTURE,
                )
                else -> ActionSpec(
                    R.drawable.ic_widget_add,
                    R.string.widget_capture_title,
                    R.string.widget_capture_subtitle,
                    MainActivity.ACTION_TEXT_CAPTURE,
                )
            }
            views.setImageViewResource(R.id.widget_disc_icon, icon)
            views.setTextViewText(R.id.widget_title, context.getString(title))
            views.setTextViewText(R.id.widget_subtitle, context.getString(subtitle))
            views.setOnClickPendingIntent(R.id.widget_root, launchPending(context, action))
            return views
        }

        private fun notesViews(context: Context, id: Int): RemoteViews {
            val t = widgetTheme(context)
            val views = RemoteViews(context.packageName, R.layout.widget_notes)
            views.setInt(R.id.widget_notes_root, "setBackgroundResource", t.cardBackground)
            views.setTextColor(R.id.notes_brand, t.text)
            views.setTextColor(R.id.notes_title, t.secondary)
            views.setInt(R.id.notes_refresh, "setColorFilter", t.secondary)
            views.setTextColor(R.id.notes_add_label, t.text)
            views.setInt(R.id.notes_add_icon, "setColorFilter", t.accent)
            views.setTextViewText(R.id.notes_title, context.getString(R.string.widget_notes_title))
            views.setTextViewText(R.id.notes_add_label, context.getString(R.string.widget_new_note))

            views.setRemoteAdapter(
                R.id.notes_list,
                Intent(context, NexWidgetNotesService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                },
            )

            views.setOnClickPendingIntent(
                R.id.notes_refresh,
                PendingIntent.getBroadcast(
                    context,
                    id,
                    Intent(context, NexNotesWidget::class.java).setAction(ACTION_REFRESH),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            views.setOnClickPendingIntent(
                R.id.notes_add,
                launchPending(context, MainActivity.ACTION_TEXT_CAPTURE),
            )
            return views
        }

        /* -------------------------------------------------------- launching */

        /** A tap on a widget or row opens Nex with a capture or open intent. */
        fun launchPending(
            context: Context,
            action: String,
            noteId: String? = null,
            requestCode: Int = 0,
        ): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                if (noteId != null) putExtra(MainActivity.EXTRA_NOTE_ID, noteId)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

/** What one one-tap widget shows: icon, two labels and the deep link. */
private data class ActionSpec(
    val icon: Int,
    val title: Int,
    val subtitle: Int,
    val action: String,
)

/** Which theme the widget chrome should use, resolved from night mode. */
data class WidgetTheme(
    val cardBackground: Int,
    val text: Int,
    val secondary: Int,
    val discNeutral: Int,
    val discAccent: Int,
    val onAccent: Int,
    val accent: Int,
    val iconTint: Int,
)

fun widgetTheme(context: Context): WidgetTheme {
    val dark =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
    return if (dark) {
        WidgetTheme(
            cardBackground = R.drawable.widget_card_bg_dark,
            text = context.getColor(R.color.nex_widget_text_dark),
            secondary = context.getColor(R.color.nex_widget_secondary_dark),
            discNeutral = R.drawable.widget_disc_neutral_dark,
            discAccent = R.drawable.widget_disc_accent_dark,
            onAccent = context.getColor(R.color.nex_widget_on_accent_dark),
            accent = context.getColor(R.color.nex_widget_accent_dark),
            iconTint = context.getColor(R.color.nex_widget_text_dark),
        )
    } else {
        WidgetTheme(
            cardBackground = R.drawable.widget_card_bg_light,
            text = context.getColor(R.color.nex_widget_text_light),
            secondary = context.getColor(R.color.nex_widget_secondary_light),
            discNeutral = R.drawable.widget_disc_neutral_light,
            discAccent = R.drawable.widget_disc_accent_light,
            onAccent = context.getColor(R.color.nex_widget_on_accent_light),
            accent = context.getColor(R.color.nex_widget_accent_light),
            iconTint = context.getColor(R.color.nex_widget_text_light),
        )
    }
}

/** The type glyph a note row carries. */
fun widgetIconFor(type: String): Int = when (type) {
    "voice" -> R.drawable.ic_widget_mic
    "photo" -> R.drawable.ic_widget_photo
    "file" -> R.drawable.ic_widget_file
    else -> R.drawable.ic_widget_notes
}

class NexQuickCaptureWidget : NexWidgetProvider() {
    override val widgetType = NexWidgetProvider.TYPE_QUICK_CAPTURE
}

class NexVoiceWidget : NexWidgetProvider() {
    override val widgetType = NexWidgetProvider.TYPE_VOICE
}

class NexCameraWidget : NexWidgetProvider() {
    override val widgetType = NexWidgetProvider.TYPE_CAMERA
}

class NexNotesWidget : NexWidgetProvider() {
    override val widgetType = NexWidgetProvider.TYPE_NOTES
}
