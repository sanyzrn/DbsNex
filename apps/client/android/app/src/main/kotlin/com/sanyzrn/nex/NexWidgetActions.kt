package com.sanyzrn.nex

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Every way a tap on a widget reaches the app, and every way the app pushes
 * fresh views back out.
 *
 * All three actions land on [MainActivity] because that is where the Dart
 * bridge lives: the activity queues the request as a pending payload and the
 * running engine delivers it into the same capture path as in-app capture
 * (FR-8.3 — OS surfaces are held to the same zero-decision rules). Text
 * capture and share-intent already worked this way; open-note joins them.
 */
object NexWidgetActions {

    /** Asks Dart to open the capture sheet on the timeline (FR-8.1). */
    const val ACTION_TEXT_CAPTURE = MainActivity.ACTION_TEXT_CAPTURE

    /** Asks Dart to open one note. Carries [EXTRA_NOTE_ID]. */
    //
    // Borrowed from [MainActivity] rather than spelled again, like the
    // capture action above it. These strings are matched against an incoming
    // intent by exact value: two copies of one of them is a pair that can
    // drift apart, and a row that silently opens nothing is what that would
    // look like.
    const val ACTION_OPEN_NOTE = MainActivity.ACTION_OPEN_NOTE

    const val EXTRA_NOTE_ID = MainActivity.EXTRA_NOTE_ID

    // Distinct request codes so the three PendingIntents can never collide:
    // PendingIntent matching is by request code and intent, and the open-note
    // template must stay separate from everything a plain tap can trigger.
    private const val RC_OPEN_APP = 0x4E650001
    private const val RC_TEXT_CAPTURE = 0x4E650002
    private const val RC_OPEN_NOTE = 0x4E650003

    private val launchFlags =
        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

    /** Opens the timeline, exactly as the launcher icon does. */
    fun openAppIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java).addFlags(launchFlags)

    /** Opens the timeline straight into text capture (FR-8.1 / ADR-027). */
    fun textCaptureIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(ACTION_TEXT_CAPTURE)
            .addFlags(launchFlags)

    /** Opens one note. The id arrives as a row's fill-in intent at tap time. */
    fun openNoteIntent(context: Context): Intent =
        Intent(context, MainActivity::class.java)
            .setAction(ACTION_OPEN_NOTE)
            .addFlags(launchFlags)

    fun openApp(context: Context): PendingIntent = activity(context, RC_OPEN_APP) {
        openAppIntent(context)
    }

    fun textCapture(context: Context): PendingIntent = activity(context, RC_TEXT_CAPTURE) {
        textCaptureIntent(context)
    }

    /**
     * The click template for the timeline list. It has to be created
     * [PendingIntent.FLAG_MUTABLE]: the fill-in intent that carries the note
     * id is merged in by the launcher at tap time, and an immutable
     * PendingIntent would silently swallow it — every row would open the app
     * with no note at all.
     */
    fun openNoteTemplate(context: Context): PendingIntent {
        val intent = openNoteIntent(context)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getActivity(context, RC_OPEN_NOTE, intent, flags)
    }

    private inline fun activity(
        context: Context,
        requestCode: Int,
        intent: () -> Intent,
    ): PendingIntent = PendingIntent.getActivity(
        context,
        requestCode,
        intent(),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Asks both widget providers to rebuild their views from the snapshot.
     *
     * An explicit broadcast carrying the widget ids routes through
     * [BroadcastReceiver] to `onUpdate` — the same path the system uses, so
     * there is exactly one rendering code path for "added", "restored" and
     * "the app changed something". `updatePeriodMillis` stays 0: freshness
     * is the app's job, and the app knows the moment its data moved.
     */
    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context) ?: return
        for (provider in listOf(CaptureWidgetProvider::class.java, TimelineWidgetProvider::class.java)) {
            val ids = manager.getAppWidgetIds(ComponentName(context, provider))
            if (ids.isEmpty()) continue
            val update = Intent(context, provider).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(update)
        }
    }
}
