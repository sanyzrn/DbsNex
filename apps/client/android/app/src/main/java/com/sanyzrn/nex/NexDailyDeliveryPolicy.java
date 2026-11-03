package com.sanyzrn.nex;

import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TimeZone;

/** Pure scheduling policy: no Android, Flutter, database or network dependency. */
public final class NexDailyDeliveryPolicy {
    private NexDailyDeliveryPolicy() {}

    public static String day(long millis, TimeZone zone) {
        Calendar date = Calendar.getInstance(zone, Locale.ROOT);
        date.setTimeInMillis(millis);
        return String.format(Locale.ROOT, "%04d-%02d-%02d", date.get(Calendar.YEAR),
            date.get(Calendar.MONTH) + 1, date.get(Calendar.DAY_OF_MONTH));
    }

    public static long next(long now, TimeZone zone, int minutes, Set<String> delivered) {
        minutes = Math.max(0, Math.min(1439, minutes));
        Calendar date = Calendar.getInstance(zone, Locale.ROOT);
        date.setTimeInMillis(now);
        date.set(Calendar.HOUR_OF_DAY, Math.max(0, Math.min(1439, minutes)) / 60);
        date.set(Calendar.MINUTE, Math.max(0, Math.min(1439, minutes)) % 60);
        date.set(Calendar.SECOND, 0);
        date.set(Calendar.MILLISECOND, 0);
        while (date.getTimeInMillis() <= now || delivered.contains(day(date.getTimeInMillis(), zone))) {
            // Calendar arithmetic preserves the selected clock time over DST.
            date.add(Calendar.DAY_OF_MONTH, 1);
            date.set(Calendar.HOUR_OF_DAY, minutes / 60);
            date.set(Calendar.MINUTE, minutes % 60);
        }
        return date.getTimeInMillis();
    }

    public static String choose(List<String> choices, String previous, int turn) {
        if (choices.isEmpty()) return "";
        int start = ((turn % choices.size()) + choices.size()) % choices.size();
        for (int i = 0; i < choices.size(); i++) {
            String text = choices.get((start + i) % choices.size());
            if (!text.equals(previous) || choices.size() == 1) return text;
        }
        return choices.get(start);
    }

    public static boolean current(long now, long expires, long generated,
                                  long invalidated, int plannedOffset, int actualOffset) {
        return now >= generated && now <= expires && generated >= invalidated && plannedOffset == actualOffset;
    }
}
