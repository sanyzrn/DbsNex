package com.sanyzrn.nex;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.text.Html;
import android.util.Log;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.TimeZone;
import java.util.TreeSet;
import org.json.JSONArray;
import org.json.JSONObject;

/** One tiny alarm, one daily ID. Delivery reads only a local dated text plan. */
public final class NexDailyNudgeReceiver extends BroadcastReceiver {
    private static final String TAG = "NexDailyNudge";
    private static final String FIRE = "com.sanyzrn.nex.DAILY_NUDGE";
    /** A second, bounded attempt at a notification the shade never received. */
    private static final String RETRY = "com.sanyzrn.nex.DAILY_NUDGE_RETRY";
    private static final String CHANNEL = "nex.daily";
    private static final String STORE = "nex.daily.plan";

    /** How many times one day may be posted, the first attempt included. */
    private static final int MAX_ATTEMPTS = 3;
    private static final long RETRY_DELAY_MS = 15 * 60 * 1000L;

    private static SharedPreferences store(Context context) {
        return context.getSharedPreferences(STORE, Context.MODE_PRIVATE);
    }

    private static SharedPreferences flutter(Context context) {
        return context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
    }

    private static PendingIntent alarmIntent(Context context) {
        return PendingIntent.getBroadcast(context, 0,
            new Intent(context, NexDailyNudgeReceiver.class).setAction(FIRE),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** Its own request code and action: a retry must never replace the alarm. */
    private static PendingIntent retryIntent(Context context) {
        return PendingIntent.getBroadcast(context, 1,
            new Intent(context, NexDailyNudgeReceiver.class).setAction(RETRY),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /**
     * Stores the plan, arms the alarm, and answers whether the OS took it.
     *
     * The answer is the caller's only evidence. A stored plan and an accepted
     * plan look identical from Dart, and this is the one place that knows the
     * difference: `false` reaches the settings banner through
     * `NexDailyNudgeNative.configure`, so a phone that refuses every kind of
     * alarm is told so instead of being promised a nudge it will never send.
     */
    public static boolean configure(Context context, String json) throws Exception {
        JSONObject plan = new JSONObject(json);
        if (plan.optInt("version") != 1) throw new IllegalArgumentException("Unsupported daily plan");
        // apply(), not commit(): the caller is a MethodChannel handler on the
        // main thread, and this value is handed straight to schedule() below,
        // so nothing waits on the disk write. A failure here cannot happen
        // for a value the OS already accepted in memory, and the plan is
        // rewritten on the next launch either way.
        store(context).edit().putString("plan", json).apply();
        return schedule(context, plan);
    }

    public static void cancel(Context context) {
        store(context).edit().remove("plan")
            .remove("alarmError").remove("alarmErrorAt")
            .remove("deliveryError").remove("deliveryErrorAt")
            .remove("retryDay").remove("retries").commit();
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        alarms.cancel(alarmIntent(context));
        alarms.cancel(retryIntent(context));
        ((NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE)).cancel(0);
    }

    /**
     * The last alarm or delivery failure, in the app's own words, or null.
     *
     * Read by Dart into the diagnostics file ("Share diagnostics") rather than
     * shown: a boot-time alarm Android refused is worth recording, and nothing
     * the reader does on the settings screen can fix a failure that already
     * happened. It is also read before the next configure, which is what keeps
     * a background failure from being overwritten by a later success.
     */
    public static String lastError(Context context) {
        SharedPreferences saved = store(context);
        String alarm = saved.getString("alarmError", null);
        String delivery = saved.getString("deliveryError", null);
        if (alarm == null && delivery == null) return null;
        long alarmAt = saved.getLong("alarmErrorAt", 0);
        long deliveryAt = saved.getLong("deliveryErrorAt", 0);
        boolean newestIsDelivery = deliveryAt >= alarmAt;
        String message = newestIsDelivery ? delivery : alarm;
        if (message == null) message = newestIsDelivery ? alarm : delivery;
        long at = Math.max(alarmAt, deliveryAt);
        return at == 0 ? message : message + " @ " + at;
    }

    private static void noteAlarmFailure(Context context, String message, Throwable error) {
        if (error == null) Log.w(TAG, message); else Log.w(TAG, message, error);
        store(context).edit().putString("alarmError", message)
            .putLong("alarmErrorAt", System.currentTimeMillis()).apply();
    }

    private static void noteDeliveryFailure(Context context, String message, Throwable error) {
        if (error == null) Log.w(TAG, message); else Log.w(TAG, message, error);
        store(context).edit().putString("deliveryError", message)
            .putLong("deliveryErrorAt", System.currentTimeMillis()).apply();
    }

    /**
     * Arms one alarm: exact when allowed, inexact otherwise.
     *
     * `false` is the one answer this class must never swallow — it means the
     * OS refused both kinds, so nothing will fire and the caller has to say so.
     */
    private static boolean setAlarm(AlarmManager manager, long at, PendingIntent intent) {
        // Same permission and fallback policy as the existing note reminders.
        if (Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()) {
            try { manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent); return true; }
            catch (SecurityException ignored) { /* permission changed concurrently */ }
            catch (RuntimeException ignored) { /* a ROM that rejects an exact alarm outright */ }
        }
        try { manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent); return true; }
        catch (RuntimeException ignored) { return false; }
    }

    /** Arms the next daily slot; false means an alarm was wanted and refused. */
    private static boolean schedule(Context context, JSONObject plan) {
        if (!plan.optBoolean("enabled")
            || !flutter(context).getBoolean("flutter.nudge.on", false)) {
            return true; // Nothing was asked for, so nothing failed.
        }
        Set<String> days = store(context).getStringSet("delivered", new HashSet<>());
        int minutes = (int) flutter(context).getLong("flutter.nudge.at", plan.optInt("minutes", 540));
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        long at = NexDailyDeliveryPolicy.next(System.currentTimeMillis(),
            TimeZone.getDefault(), minutes, days);
        if (setAlarm(manager, at, alarmIntent(context))) {
            // The alarm this failure was about has been replaced by one the OS
            // accepted, so the untaken alarm is no longer the current state.
            store(context).edit().remove("alarmError").remove("alarmErrorAt").apply();
            return true;
        }
        // No alarm at all. The plan and the preferences stay where they are so
        // the next launch or boot can try again; the failure is recorded and
        // reported rather than swallowed.
        noteAlarmFailure(context, "the system did not keep the daily alarm",
            new IllegalStateException("no alarm accepted before " + at));
        return false;
    }

    @Override public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        try {
            String json = store(context).getString("plan", null);
            if (json == null) return;
            JSONObject plan = new JSONObject(json);
            if (!flutter(context).getBoolean("flutter.nudge.on", false)) { cancel(context); return; }
            if (FIRE.equals(action) || RETRY.equals(action)) {
                try {
                    deliver(context, plan, RETRY.equals(action));
                } catch (Exception error) {
                    // Recorded, not retried blindly: an unreadable plan would
                    // fail the same way every fifteen minutes.
                    noteDeliveryFailure(context, "delivery failed", error);
                }
            }
            schedule(context, plan);
        } catch (Exception error) {
            // A malformed or removed plan never affects any other reminder.
            noteAlarmFailure(context, "daily plan unreadable", error);
        }
    }

    private static List<String> strings(JSONArray array) {
        List<String> values = new ArrayList<>();
        if (array != null) for (int i = 0; i < array.length(); i++) {
            String text = array.optString(i, "").trim();
            if (!text.isEmpty()) values.add(text);
        }
        return values;
    }

    private static CharSequence text(String html) {
        return Build.VERSION.SDK_INT >= 24
            ? Html.fromHtml(html, Html.FROM_HTML_MODE_LEGACY) : Html.fromHtml(html);
    }

    private static void deliver(Context context, JSONObject plan, boolean retry) throws Exception {
        NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED) return;
        if (Build.VERSION.SDK_INT >= 24 && !manager.areNotificationsEnabled()) return;
        long now = System.currentTimeMillis();
        TimeZone zone = TimeZone.getDefault();
        String today = NexDailyDeliveryPolicy.day(now, zone);
        SharedPreferences saved = store(context);
        TreeSet<String> delivered = new TreeSet<>(saved.getStringSet("delivered", new HashSet<>()));
        if (delivered.contains(today)) return;
        if (retry) {
            // The retry belongs to one date. After midnight its text is no
            // longer today's, and today's own alarm is already armed.
            String planned = saved.getString("retryDay", null);
            if (planned == null || !planned.equals(today)) return;
        }
        SharedPreferences prefs = flutter(context);
        JSONObject days = plan.optJSONObject("days");
        JSONObject dated = days == null ? null : days.optJSONObject(today);
        long generated = plan.optLong("generatedAt");
        long invalidated = prefs.getLong("flutter.dailyNudge.invalidatedAt", 0);
        int plannedOffset = dated == null ? plan.optInt("zone")
            : dated.optInt("zone", plan.optInt("zone"));
        int actualOffset = zone.getOffset(now) / 60000;
        List<String> pool = new ArrayList<>();
        if (dated != null) {
            // The plan's own text is used only for the day it describes, in
            // the zone it was planned for, and while it is still true. Local
            // facts hold until that day ends — an exact alarm can arrive
            // hours late, and today's reminders are better late than replaced
            // by a generic line. A recap keeps its one-hour freshness, and
            // when it has expired the day's local bodies still apply.
            long localLimit = dated.optLong("localExpires", dated.optLong("expires"));
            if (NexDailyDeliveryPolicy.current(now, localLimit, generated, invalidated,
                plannedOffset, actualOffset)) {
                pool = strings(dated.optJSONArray("localBodies"));
                boolean consent = !plan.optBoolean("includesHabits")
                    || (prefs.getBoolean("flutter.brief.useHabits", false)
                        && prefs.getBoolean("flutter.module.habits.on", false));
                boolean ai = consent && dated.optBoolean("ai")
                    && prefs.getBoolean("flutter.ai.enabled", false)
                    && prefs.getBoolean("flutter.home.day_summary", true)
                    && NexDailyDeliveryPolicy.current(now,
                        dated.optLong("expires", localLimit), generated, invalidated,
                        plannedOffset, actualOffset);
                List<String> recap = ai
                    ? strings(dated.optJSONArray("bodies")) : new ArrayList<String>();
                if (!recap.isEmpty()) pool = recap;
            }
        }
        if (pool.isEmpty()) pool = strings(plan.optJSONArray("fallback"));
        String body = NexDailyDeliveryPolicy.choose(pool,
            saved.getString("lastBody", ""), saved.getInt("turn", 0));
        // An empty pool used to end the day in silence: nothing was posted
        // and nothing was marked, so the alarm simply moved on to tomorrow. A
        // plan with no text at all is now the only case that does that.
        if (body.isEmpty()) return;
        String channelName = plan.optString("channelName", "").trim();
        if (channelName.isEmpty()) channelName = "Nex";
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = manager.getNotificationChannel(CHANNEL);
            if (channel == null) {
                manager.createNotificationChannel(new NotificationChannel(CHANNEL,
                    channelName, NotificationManager.IMPORTANCE_DEFAULT));
                channel = manager.getNotificationChannel(CHANNEL);
            } else if (!channelName.contentEquals(channel.getName())) {
                // Android fixes a channel's sound and importance when it is
                // created, but lets the app rename it. The plan is the only
                // place that knows the app's language, so a channel created
                // before a language change kept its old name for good.
                channel.setName(channelName);
                manager.createNotificationChannel(channel);
            }
            if (channel == null
                || channel.getImportance() == NotificationManager.IMPORTANCE_NONE) return;
        }
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        PendingIntent tap = null;
        if (open != null) {
            open.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            tap = PendingIntent.getActivity(context, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        }
        int icon = context.getResources().getIdentifier("ic_stat_nex", "drawable", context.getPackageName());
        if (icon == 0) icon = context.getApplicationInfo().icon;
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(context, CHANNEL) : new Notification.Builder(context);
        builder.setSmallIcon(icon).setContentTitle(text(plan.optString("title", "Nex")))
            .setContentText(text(body)).setStyle(new Notification.BigTextStyle().bigText(text(body)))
            .setAutoCancel(true).setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(prefs.getBoolean("flutter.security.app_lock", false)
                ? Notification.VISIBILITY_SECRET : Notification.VISIBILITY_PRIVATE);
        // A device whose launcher intent cannot be resolved still deserves
        // the notification; it just has nothing to open.
        if (tap != null) builder.setContentIntent(tap);
        delivered.add(today);
        delivered = new TreeSet<>(NexDailyDeliveryPolicy.recent(delivered, 32));
        // Persist before posting: duplicate broadcasts and time changes cannot
        // emit twice for a date, even when the activity has never been opened.
        if (!saved.edit().putStringSet("delivered", delivered).putString("lastBody", body)
            .putInt("turn", saved.getInt("turn", 0) + 1).commit()) return;
        try {
            manager.notify(0, builder.build());
            // It reached the shade, so the day is spent exactly once and any
            // earlier failure is no longer the current state.
            saved.edit().remove("retryDay").remove("retries")
                .remove("deliveryError").remove("deliveryErrorAt").apply();
        } catch (RuntimeException error) {
            // Nothing reached the shade, so the day is not spent: leaving the
            // date marked would lose the nudge until tomorrow. Put it back,
            // record why, and try again later today at most twice — each retry
            // still tests the same receipt, so a duplicate is impossible.
            TreeSet<String> retryPool = new TreeSet<>(saved.getStringSet("delivered", new HashSet<>()));
            retryPool.remove(today);
            saved.edit().putStringSet("delivered", retryPool).commit();
            noteDeliveryFailure(context, "notification was not shown", error);
            armRetry(context, today, now);
        }
    }

    /**
     * Schedules the next same-day attempt, or gives up.
     *
     * Bounded by [MAX_ATTEMPTS] and by midnight, both decided by the pure
     * policy, so a phone whose shade refuses every post cannot become a retry
     * loop. The attempt count lives with the date it belongs to.
     */
    private static void armRetry(Context context, String today, long now) {
        SharedPreferences saved = store(context);
        int attempts = today.equals(saved.getString("retryDay", null))
            ? saved.getInt("retries", 0) : 0;
        attempts++;
        saved.edit().putString("retryDay", today).putInt("retries", attempts).commit();
        long at = NexDailyDeliveryPolicy.retryAt(now, TimeZone.getDefault(), today,
            attempts, MAX_ATTEMPTS, RETRY_DELAY_MS);
        if (at < 0) return;
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (!setAlarm(manager, at, retryIntent(context))) {
            // The OS refused the retry as well. The failure is already
            // recorded; a later boot or time change still re-arms the daily
            // alarm, so the feature is not lost.
            noteAlarmFailure(context, "the system did not keep the retry alarm", null);
        }
    }
}
