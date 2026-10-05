package com.sanyzrn.nex

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.SystemClock
import java.util.UUID

/**
 * A copy of a secret that erases itself after [LIFETIME_MS].
 *
 * The wipe used to be a main-looper callback, which dies with the process: copy
 * a password, switch to the browser, and if Android reclaimed Nex meanwhile the
 * password stayed on the clipboard for good. Now the copy is also written down
 * (marker and deadline) and an alarm is set, so the wipe survives the process,
 * and every return to the foreground sweeps a copy whose time has passed.
 *
 * Android 10 and later let only the app in the foreground read the clipboard,
 * so there the alarm cannot check whose copy it is and leaves it alone; the
 * sweep on the next return to Nex erases it. Erasing without checking would
 * risk wiping something the person copied since, which is worse.
 */
object NexPrivateClipboard {
    private const val LIFETIME_MS = 30_000L
    private const val STORE = "nex_private_clipboard"
    private const val KEY_MARKER = "marker"
    private const val KEY_DEADLINE = "deadline"

    fun copy(context: Context, text: String) {
        val app = context.applicationContext
        val manager = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val marker = "Nex-private-${UUID.randomUUID()}"
        val clip = ClipData.newPlainText(marker, text)
        clip.description.extras = PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
        manager.setPrimaryClip(clip)
        app.getSharedPreferences(STORE, Context.MODE_PRIVATE).edit()
            .putString(KEY_MARKER, marker)
            .putLong(KEY_DEADLINE, System.currentTimeMillis() + LIFETIME_MS)
            .apply()
        runCatching {
            val alarms = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + LIFETIME_MS,
                wipeIntent(app),
            )
        }
        Handler(Looper.getMainLooper()).postDelayed({ sweep(app) }, LIFETIME_MS)
    }

    /**
     * Erases Nex's last private copy if its time has passed and it is still
     * what the clipboard holds. Safe to call at any moment; a copy that is not
     * due yet is left for its own alarm. [foreground] says the clipboard can
     * be read, so that finding nothing there means it is empty.
     */
    fun sweep(context: Context, foreground: Boolean = false) {
        runCatching {
            val app = context.applicationContext
            val store = app.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val marker = store.getString(KEY_MARKER, null) ?: return
            if (System.currentTimeMillis() < store.getLong(KEY_DEADLINE, 0L)) return
            val manager = app.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            // Null when the clipboard is empty, and also when Android will not
            // let a background app look: then keep the record for the sweep
            // on the next return to Nex.
            val label = manager.primaryClipDescription?.label?.toString()
            if (label == null && !foreground) return
            // Never erase a later copy belonging to the user or another app.
            if (label == marker) {
                if (Build.VERSION.SDK_INT >= 28) manager.clearPrimaryClip()
                else manager.setPrimaryClip(ClipData.newPlainText("", ""))
            }
            store.edit().clear().apply()
        }
    }

    private fun wipeIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, NexClipboardWipeReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** Fired by the alarm [NexPrivateClipboard.copy] sets. */
class NexClipboardWipeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NexPrivateClipboard.sweep(context)
    }
}
