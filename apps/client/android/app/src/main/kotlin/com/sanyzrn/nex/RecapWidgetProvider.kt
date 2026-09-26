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
 * The Recap widget: the assistant's brief on the home screen, and nothing
 * else.
 *
 * The brief is the answer to "is anything waiting on me" — a few emoji-led
 * lines, overdue first — and that question is worth asking without opening
 * anything. The Timeline widget answers a different one ("what did I write"),
 * which is why this is a second widget rather than a band across that one.
 *
 * Everything it shows comes from the snapshot file Dart writes
 * ([NexWidgetSnapshot]); nothing here reads the database, and nothing here
 * can generate a brief. **That last part is the whole design of the refresh
 * button.** Writing a brief means asking a model, and a widget provider is a
 * broadcast receiver with about ten seconds to live and no Flutter engine
 * behind it — so the button sends [NexWidgetActions.ACTION_REFRESH_RECAP],
 * which opens Nex, and the timeline forces its own recap refresh exactly as
 * its own refresh button does. The new brief reaches the home screen a moment
 * later through the snapshot. The button's content description says so, so a
 * screen reader announces the app opening rather than being surprised by it.
 *
 * Three states, checked in this order, mirroring [TimelineWidgetProvider]:
 *
 *  - **Locked** — the app lock is closed. There is no brief on disk to show:
 *    the snapshot carries none while the lock is closed, because a brief is
 *    made of what the notes say.
 *  - **Empty** — no brief yet. The app has never written one (AI off, or
 *    never opened since it was turned on), or there is no snapshot at all.
 *    A prompt toward the refresh button, which is the thing that fixes it.
 *  - **Content** — the brief, as the lines it was written in.
 */
class RecapWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, views(context))
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle?,
    ) {
        // The body is one TextView filling whatever height the launcher
        // grants, so nothing about it reflows with size. Re-rendering keeps
        // the rest of the frame honest after a resize all the same.
        manager.updateAppWidget(id, views(context))
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

    private fun views(context: Context): RemoteViews {
        val displayContext = NexWidgetAppearance.localized(context)
        val views = RemoteViews(context.packageName, R.layout.widget_recap)
        views.setInt(R.id.nex_recap_root, "setLayoutDirection", displayContext.resources.configuration.layoutDirection)
        val snapshot = NexWidgetSnapshot.read(context)
        NexWidgetAppearance.accent(context)?.let {
            views.setInt(R.id.nex_recap_glyph, "setColorFilter", it)
        }

        // The header is common to every state. Both of its controls survive
        // the lock: the title opens the app, which gates itself, and refresh
        // does the same thing plus an errand.
        views.setTextViewText(
            R.id.nex_recap_title,
            displayContext.getString(R.string.widget_recap_title),
        )
        views.setOnClickPendingIntent(
            R.id.nex_recap_header,
            NexWidgetActions.openApp(context),
        )
        views.setOnClickPendingIntent(
            R.id.nex_recap_refresh,
            NexWidgetActions.refreshRecap(context),
        )
        views.setContentDescription(
            R.id.nex_recap_refresh,
            displayContext.getString(R.string.widget_a11y_recap_refresh),
        )
        views.setOnClickPendingIntent(
            R.id.nex_recap_root,
            NexWidgetActions.openApp(context),
        )

        val recap = snapshot?.recap.orEmpty()
        when {
            snapshot?.appLock == true -> {
                show(views, R.id.nex_recap_locked)
                views.setTextViewText(
                    R.id.nex_recap_locked_text,
                    displayContext.getString(R.string.widget_recap_locked_title),
                )
                views.setContentDescription(
                    R.id.nex_recap_locked,
                    displayContext.getString(R.string.widget_recap_locked_a11y),
                )
            }
            recap.isEmpty() -> {
                show(views, R.id.nex_recap_empty)
                views.setTextViewText(
                    R.id.nex_recap_empty_title,
                    displayContext.getString(R.string.widget_recap_empty_title),
                )
                views.setTextViewText(
                    R.id.nex_recap_empty_hint,
                    displayContext.getString(R.string.widget_recap_empty_hint),
                )
            }
            else -> {
                show(views, R.id.nex_recap_body)
                views.setTextViewText(R.id.nex_recap_body, recap)
                // The brief already reads as a list; a screen reader gets the
                // same lines rather than a second, differently-worded summary
                // of them.
                views.setContentDescription(R.id.nex_recap_body, recap)
            }
        }
        return views
    }

    /**
     * Shows exactly one of the three bodies.
     *
     * Written as "hide all, then show one" rather than as three visibility
     * calls per branch: RemoteViews are cumulative on the host side, and a
     * branch that forgot one of its two GONEs would leave two bodies stacked
     * on a widget nobody had rebuilt from scratch.
     */
    private fun show(views: RemoteViews, id: Int) {
        for (body in BODIES) {
            views.setViewVisibility(body, if (body == id) View.VISIBLE else View.GONE)
        }
    }

    private companion object {
        val BODIES = intArrayOf(
            R.id.nex_recap_body,
            R.id.nex_recap_locked,
            R.id.nex_recap_empty,
        )
    }
}
