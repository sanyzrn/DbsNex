package com.sanyzrn.nex

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app's process running while an installer is being downloaded.
 *
 * The transfer itself is Dart's, and it already survived leaving the update
 * screen. What it did not survive was leaving the *app*: Android suspends the
 * process soon after the last window goes away, and the download stopped
 * wherever it had got to. A notification is not enough to prevent that — an
 * ordinary one is just a row in the shade — but a foreground service is, and
 * a foreground service is required to post one of its own.
 *
 * So this owns the progress notification as well. Two would be worse than
 * one, and the Dart side's own progress notification is skipped whenever this
 * takes the job (see `NexDownloadNotice`). The "ready to install" notification
 * that follows a finished download stays on the Dart side, under its own id:
 * it has to outlive the service, and it is the one that is meant to be tapped.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty().ifEmpty { "Nex" }
        val percent = intent?.getIntExtra(EXTRA_PERCENT, 0) ?: 0
        val notification = build(this, title, percent)
        // The type is declared in the manifest as well; API 34 wants it named
        // at the call too, or it refuses to start the service at all.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        running = true
        // Not sticky. If Android does kill this, the download died with the
        // process it was keeping alive, and restarting an empty service would
        // put a progress bar on screen for a transfer that is not running.
        // Coming back to the app resumes it from the `.part` on disk instead.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    companion object {
        /**
         * Whether the service is up.
         *
         * Read before every progress update, and the reason is Android 12's
         * rule rather than efficiency: starting a foreground service from the
         * background throws, and every update after the first one arrives
         * from the background by definition — that is the situation this
         * whole class exists for. So the first call starts the service, from
         * the foreground where it is allowed, and the rest only rewrite the
         * notification, which nothing restricts.
         */
        @Volatile
        var running = false

        /** Id 4: the Dart side's own update notification is 3. */
        private const val ID = 4

        /**
         * The same channel `NexReminders` uses for the update notifications,
         * so this is one line in the app's notification settings and not two.
         */
        private const val CHANNEL = "nex.updates"

        const val EXTRA_TITLE = "title"
        const val EXTRA_PERCENT = "percent"

        /** Rewrites the notification of a service that is already running. */
        fun update(context: Context, title: String, percent: Int) {
            manager(context).notify(ID, build(context, title, percent))
        }

        private fun manager(context: Context): NotificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        @Suppress("DEPRECATION")
        private fun build(context: Context, title: String, percent: Int): Notification {
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Created here rather than left to whichever half posts first:
                // this service can be the first thing to use the channel on a
                // fresh install, and a notification on a channel that does not
                // exist is dropped silently.
                manager(context).createNotificationChannel(
                    NotificationChannel(
                        CHANNEL,
                        "Updates",
                        NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = "Downloading a new version of Nex"
                        setShowBadge(false)
                    },
                )
                Notification.Builder(context, CHANNEL)
            } else {
                Notification.Builder(context)
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            return builder
                .setSmallIcon(R.drawable.ic_stat_nex)
                .setContentTitle(title)
                .setContentText("$percent%")
                .setProgress(100, percent.coerceIn(0, 100), false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .build()
        }
    }
}
