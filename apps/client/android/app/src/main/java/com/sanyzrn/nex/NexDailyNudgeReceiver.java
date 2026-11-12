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
    private static final String FIRE = "com.sanyzrn.nex.DAILY_NUDGE";
    private static final String CHANNEL = "nex.daily";
    private static final String STORE = "nex.daily.plan";

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

    public static void configure(Context context, String json) throws Exception {
        JSONObject plan = new JSONObject(json);
        if (plan.optInt("version") != 1) throw new IllegalArgumentException("Unsupported daily plan");
        // apply(), not commit(): the caller is a MethodChannel handler on the
        // main thread, and this value is handed straight to schedule() below,
        // so nothing waits on the disk write. A failure here cannot happen
        // for a value the OS already accepted in memory, and the plan is
        // rewritten on the next launch either way.
        store(context).edit().putString("plan", json).apply();
        schedule(context, plan);
    }

    public static void cancel(Context context) {
        store(context).edit().remove("plan").commit();
        ((AlarmManager) context.getSystemService(Context.ALARM_SERVICE)).cancel(alarmIntent(context));
        ((NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE)).cancel(0);
    }

    private static void schedule(Context context, JSONObject plan) {
        if (!plan.optBoolean("enabled") || !flutter(context).getBoolean("flutter.nudge.on", false)) return;
        Set<String> days = store(context).getStringSet("delivered", new HashSet<>());
        int minutes = (int) flutter(context).getLong("flutter.nudge.at", plan.optInt("minutes", 540));
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent intent = alarmIntent(context);
        long at = NexDailyDeliveryPolicy.next(System.currentTimeMillis(),
            TimeZone.getDefault(), minutes, days);
        // Same permission and fallback policy as the existing note reminders.
        if (Build.VERSION.SDK_INT < 31 || manager.canScheduleExactAlarms()) {
            try { manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent); return; }
            catch (SecurityException ignored) { /* permission changed concurrently */ }
            catch (RuntimeException ignored) { /* a ROM that rejects an exact alarm outright */ }
        }
        try {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, intent);
        } catch (RuntimeException ignored) {
            // The OS refused both kinds. The stored plan and preferences stay
            // as they are, so the next launch or boot re-arms it; throwing
            // here would only lose the alarm that was already set.
        }
    }

    @Override public void onReceive(Context context, Intent intent) {
        try {
            String json = store(context).getString("plan", null);
            if (json == null) return;
            JSONObject plan = new JSONObject(json);
            if (!flutter(context).getBoolean("flutter.nudge.on", false)) { cancel(context); return; }
            if (FIRE.equals(intent.getAction())) {
                try { deliver(context, plan); } catch (Exception ignored) { /* retry the next day */ }
            }
            schedule(context, plan);
        } catch (Exception ignored) {
            // A malformed/removed plan never affects any other reminder.
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

    private static void deliver(Context context, JSONObject plan) throws Exception {
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
        // and nothing was marked, so the alarm simply moved to tomorrow. A
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
        } catch (RuntimeException error) {
            // Nothing reached the shade, so the day is not spent: leaving the
            // date marked would lose the nudge until tomorrow. The rollback
            // lets the next broadcast (a time change, a reboot, an app open)
            // deliver it.
            TreeSet<String> retry = new TreeSet<>(saved.getStringSet("delivered", new HashSet<>()));
            retry.remove(today);
            saved.edit().putStringSet("delivered", retry).commit();
        }
    }
}
