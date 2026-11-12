package com.sanyzrn.nex;

import java.util.Arrays;
import java.util.Calendar;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.TimeZone;

/** Executed by tools/daily_nudge_native_test.py, without an emulator or JUnit. */
public final class NexDailyDeliveryPolicyTest {
    private static int checks = 0;
    private static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    private static long time(TimeZone zone, int year, int month, int day, int hour, int minute) {
        Calendar c = Calendar.getInstance(zone);
        c.clear(); c.set(year, month - 1, day, hour, minute);
        return c.getTimeInMillis();
    }
    public static void main(String[] args) {
        TimeZone zone = TimeZone.getTimeZone("Asia/Tehran");
        long early = time(zone, 2026, 11, 3, 8, 0);
        long today = time(zone, 2026, 11, 3, 9, 0);
        check(NexDailyDeliveryPolicy.next(early, zone, 540, Collections.emptySet()) == today, "today's chosen slot");
        check(NexDailyDeliveryPolicy.next(today, zone, 540, Collections.emptySet()) == time(zone, 2026, 11, 4, 9, 0), "no immediate catch-up at/past slot");
        Set<String> sent = new HashSet<>(Arrays.asList("2026-11-03"));
        check(NexDailyDeliveryPolicy.next(early, zone, 11 * 60, sent) == time(zone, 2026, 11, 4, 11, 0), "time change must not duplicate today's nudge");
        TimeZone ny = TimeZone.getTimeZone("America/New_York");
        long spring = time(ny, 2026, 3, 8, 3, 30);
        check(NexDailyDeliveryPolicy.next(spring, ny, 150, Collections.emptySet()) == time(ny, 2026, 3, 9, 2, 30), "restore selected clock after DST gap");
        long fall = time(ny, 2026, 11, 1, 1, 45);
        check(NexDailyDeliveryPolicy.next(fall, ny, 90, new HashSet<>(Arrays.asList("2026-11-01"))) == time(ny, 2026, 11, 2, 1, 30), "DST fold cannot send twice");
        check(NexDailyDeliveryPolicy.current(200, 300, 100, 90, 210, 210), "current dated plan accepted");
        check(!NexDailyDeliveryPolicy.current(301, 300, 100, 90, 210, 210), "expired text discarded");
        check(!NexDailyDeliveryPolicy.current(200, 300, 100, 101, 210, 210), "background Done invalidates dated facts");
        check(!NexDailyDeliveryPolicy.current(200, 300, 100, 90, 210, 180), "zone change falls back safely");
        check(!NexDailyDeliveryPolicy.current(50, 300, 100, 90, 210, 210), "future cache after clock rollback is rejected");
        List<String> messages = Arrays.asList("one", "two", "three", "four", "five");
        String last = "";
        Set<String> all = new HashSet<>();
        for (int i = 0; i < 15; i++) {
            String body = NexDailyDeliveryPolicy.choose(messages, last, i);
            check(!body.equals(last), "no consecutive empty-library message");
            all.add(body); last = body;
        }
        check(all.size() == 5, "all five prompts rotate");
        check(!NexDailyDeliveryPolicy.choose(messages, "one", 0).equals("one"), "avoid same text after reschedule/restart");

        // A delayed delivery still has that day's text: the window runs to
        // the end of the day now, not one hour past the slot.
        long slot = time(zone, 2026, 11, 3, 9, 0);
        long dayEnd = time(zone, 2026, 11, 4, 0, 0) - 1;
        long built = time(zone, 2026, 11, 3, 8, 0);
        check(NexDailyDeliveryPolicy.current(slot + 8 * 3600000L, dayEnd, built, 0, 210, 210),
            "a late local delivery still has today's text");
        check(!NexDailyDeliveryPolicy.current(dayEnd + 1, dayEnd, built, 0, 210, 210),
            "a local body never outlives its day");
        check(NexDailyDeliveryPolicy.current(time(zone, 2026, 11, 3, 15, 0),
            time(zone, 2026, 11, 3, 16, 0), built, 0, 210, 210), "a recap keeps its own window");

        // Receipts are bounded, so the stored set cannot grow forever.
        Set<String> many = new HashSet<>();
        for (int i = 0; i < 100; i++) {
            many.add(NexDailyDeliveryPolicy.day(early + i * 86400000L, zone));
        }
        Set<String> kept = NexDailyDeliveryPolicy.recent(many, 32);
        check(kept.size() == 32, "delivery receipts are bounded");
        check(kept.contains(NexDailyDeliveryPolicy.day(early + 99 * 86400000L, zone)),
            "the newest receipt is kept");
        check(!kept.contains(NexDailyDeliveryPolicy.day(early, zone)), "the oldest receipts are dropped");
        // A corrupt receipt set cannot spin the receiver forever.
        check(NexDailyDeliveryPolicy.next(early, zone, 540, many) > early,
            "a corrupt receipt set still yields a future slot");
        // A failed post may try again later that day — within budget, and
        // never past midnight.
        check(NexDailyDeliveryPolicy.retryAt(slot + 3600000L, zone, "2026-11-03", 1, 3, 900000L)
            == slot + 3600000L + 900000L, "a failed delivery retries later the same day");
        check(NexDailyDeliveryPolicy.retryAt(slot, zone, "2026-11-03", 3, 3, 900000L) < 0,
            "the attempt budget is spent");
        check(NexDailyDeliveryPolicy.retryAt(slot, zone, "2026-11-02", 1, 3, 900000L) < 0,
            "a stale day is not retried");
        check(NexDailyDeliveryPolicy.retryAt(time(zone, 2026, 11, 3, 23, 55), zone,
            "2026-11-03", 1, 3, 900000L) < 0, "a retry never lands on the next day");
        System.out.println("Daily Nudge policy: " + checks + " assertions passed.");
    }
}
