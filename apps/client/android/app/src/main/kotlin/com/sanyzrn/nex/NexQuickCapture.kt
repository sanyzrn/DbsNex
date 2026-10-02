package com.sanyzrn.nex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build

/**
 * The quick-capture notification: an optional, silent, always-there row in the
 * notification shade with Note, Voice and Photo buttons (W5.2).
 *
 * Off unless the person turns it on in Settings → Capture. The choice is kept
 * here, natively, as well as in Dart's settings, because the notification has
 * to come back after a reboot, and at boot there is no Flutter engine to ask.
 *
 * Every button lands on [MainActivity] with the widget's capture action plus a
 * [EXTRA_CAPTURE_MODE], so the notification is one more way into the capture
 * path the widget already uses, not a second one.
 */
object NexQuickCapture {
    const val EXTRA_CAPTURE_MODE = "capture_mode"
    const val MODE_TEXT = "text"
    const val MODE_VOICE = "voice"
    const val MODE_PHOTO = "photo"

    // The Timeline widget's capture row reaches two more kinds than the
    // notification's three buttons have room for.
    const val MODE_GALLERY = "gallery"
    const val MODE_CHECKLIST = "checklist"

    private const val CHANNEL_ID = "nex_quick_capture"
    private const val NOTIFICATION_ID = 0x4E65_0C01
    private const val PREFS = "nex_quick_capture"
    private const val KEY_ENABLED = "enabled"

    private const val RC_SHEET = 0x4E650011
    private const val RC_TEXT = 0x4E650012
    private const val RC_VOICE = 0x4E650013
    private const val RC_PHOTO = 0x4E650014

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) post(context) else cancel(context)
    }

    /** Puts it back if it was on — at boot, after an update, at launch. */
    fun restore(context: Context) {
        val enabled = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)
        if (enabled) post(context)
    }

    private fun cancel(context: Context) {
        manager(context).cancel(NOTIFICATION_ID)
    }

    private fun manager(context: Context) =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun post(context: Context) {
        val manager = manager(context)
        // In the app's language, as the widgets are, not the phone's (LOC-03).
        // Re-posted from `pushWidgets` when that language changes; the
        // channel's name follows too, since re-creating a channel may rename
        // it.
        val text = NexWidgetAppearance.localized(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // The lowest importance that still shows in the shade: no sound,
            // no vibration, no status-bar icon, no heads-up.
            val channel = NotificationChannel(
                CHANNEL_ID,
                text.getString(R.string.quick_capture_channel),
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = text.getString(R.string.quick_capture_channel_description)
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_MIN)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_nex)
            .setContentTitle(text.getString(R.string.quick_capture_title))
            .setContentText(text.getString(R.string.quick_capture_text))
            .setContentIntent(launch(context, RC_SHEET, null))
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(action(context, text, RC_TEXT, MODE_TEXT, R.string.quick_capture_note))
            .addAction(action(context, text, RC_VOICE, MODE_VOICE, R.string.quick_capture_voice))
            .addAction(action(context, text, RC_PHOTO, MODE_PHOTO, R.string.quick_capture_photo))
            .build()
        runCatching { manager.notify(NOTIFICATION_ID, notification) }
    }

    private fun action(context: Context, text: Context, requestCode: Int, mode: String, label: Int) =
        Notification.Action.Builder(
            null as Icon?,
            text.getString(label),
            launch(context, requestCode, mode),
        )
            .build()

    private fun launch(context: Context, requestCode: Int, mode: String?): PendingIntent {
        val intent = NexWidgetActions.textCaptureIntent(context)
        if (mode != null) intent.putExtra(EXTRA_CAPTURE_MODE, mode)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/** Brings the quick-capture notification back after a reboot or an update. */
class NexQuickCaptureRestore : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> NexQuickCapture.restore(context)
        }
    }
}
