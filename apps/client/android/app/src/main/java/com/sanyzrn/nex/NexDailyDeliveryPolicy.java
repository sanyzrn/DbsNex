package com.sanyzrn.nex;

import java.util.Calendar;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.TimeZone;
import java.util.TreeSet;

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
        date.set(Calendar.HOUR_OF_DAY, minutes / 60);
        date.set(Calendar.MINUTE, minutes % 60);
        date.set(Calendar.SECOND, 0);
        date.set(Calendar.MILLISECOND, 0);
        // Bounded rather than a while loop: a receipt set corrupted by a
        // clock moved far forward and back must cost a skipped slot, not a
        // hung broadcast receiver. Calendar arithmetic preserves the selected
        // clock time over DST.
        for (int attempt = 0; attempt < 400; attempt++) {
            if (date.getTimeInMillis() > now
                && !delivered.contains(day(date.getTimeInMillis(), zone))) {
                return date.getTimeInMillis();
            }
            date.add(Calendar.DAY_OF_MONTH, 1);
            date.set(Calendar.HOUR_OF_DAY, minutes / 60);
            date.set(Calendar.MINUTE, minutes % 60);
        }
        return date.getTimeInMillis();
    }

    /**
     * When to try the same day's delivery again, or -1 when it is not worth it.
     *
     * A notification the shade never received is not a reason to lose the day,
     * but an unbounded retry is a reason to lose the phone's battery. The
     * budget is spent after [maxAttempts] posts, and a retry that would land on
     * the next local day is dropped rather than posting tomorrow's text early
     * — [plannedDay] is the date the attempt belongs to, and [attempts] counts
     * the posts already made, this one included.
     */
    public static long retryAt(long now, TimeZone zone, String plannedDay,
                               int attempts, int maxAttempts, long delay) {
        if (plannedDay == null || !day(now, zone).equals(plannedDay)) return -1;
        if (attempts >= Math.max(1, maxAttempts)) return -1;
        long at = now + Math.max(1000L, delay);
        return day(at, zone).equals(plannedDay) ? at : -1;
    }

    /** The newest [keep] delivery dates, so the receipt set cannot grow forever. */
    public static Set<String> recent(Set<String> delivered, int keep) {
        TreeSet<String> ordered = new TreeSet<>(delivered);
        int limit = Math.max(1, keep);
        while (ordered.size() > limit) ordered.pollFirst();
        return ordered;
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
