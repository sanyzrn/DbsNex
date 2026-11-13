package com.sanyzrn.nex

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.LocalDate

/**
 * The phase arithmetic the Cycle widgets draw from, on the JVM.
 *
 * Every word the widgets say — "12 days until your period", "Period, day
 * 2", "Week 15, day 0" — is this object's answer for one day, so the
 * answer has to survive any refactor of [NexCycleToday] untouched. The
 * cases below are the boundaries the widget picker's preview promises and
 * the phases a real cycle walks through, each pinned to a real date
 * rather than a clock, because the only input that matters is the
 * distance between two days.
 *
 * Run with `./gradlew testDebugUnitTest`. Pure java.time, no Android
 * classes: [NexCycleToday] takes a data class and a date and answers
 * with numbers, which is exactly why it is testable at all.
 */
class NexCycleTodayTest {

    private fun ready(
        lastStart: LocalDate?,
        periodEnd: LocalDate? = null,
        averageCycle: Int? = 28,
        averagePeriod: Int? = 5,
        nextStart: LocalDate? = lastStart?.plusDays(28),
        fertileStart: LocalDate? = lastStart?.plusDays(11),
        fertileEnd: LocalDate? = lastStart?.plusDays(16),
        ovulation: LocalDate? = lastStart?.plusDays(14),
        pregnancyStart: LocalDate? = null,
        mode: String = "normal",
    ): NexCycleSnapshot = NexCycleSnapshot(
        state = "ready",
        mode = mode,
        lastStart = lastStart,
        periodEnd = periodEnd,
        averageCycle = averageCycle,
        averagePeriod = averagePeriod,
        nextStart = nextStart,
        fertileStart = fertileStart,
        fertileEnd = fertileEnd,
        ovulation = ovulation,
        pregnancyStart = pregnancyStart,
    )

    /** A five-day period that ran its course: the shape every non-period
     * phase is reached from. */
    private fun pastPeriod(lastStart: LocalDate, days: Int = 5): LocalDate? =
        lastStart.plusDays(days)

    @Test
    fun noSnapshotIsOff() {
        assertEquals(NexCycleToday.Phase.OFF, NexCycleToday.of(null, LocalDate.of(2026, 11, 14)).phase)
    }

    @Test
    fun offSetupAndLockedStatesNeverReachTheMath() {
        assertEquals(
            NexCycleToday.Phase.OFF,
            NexCycleToday.of(ready(null).copy(state = "off"), LocalDate.of(2026, 11, 14)).phase,
        )
        assertEquals(
            NexCycleToday.Phase.LOCKED,
            NexCycleToday.of(ready(null).copy(state = "locked"), LocalDate.of(2026, 11, 14)).phase,
        )
        assertEquals(
            NexCycleToday.Phase.SETUP,
            NexCycleToday.of(ready(null).copy(state = "setup"), LocalDate.of(2026, 11, 14)).phase,
        )
    }

    @Test
    fun noPeriodYetIsEmptyAndAPeriodInTheFutureIsToo() {
        // Ready, but nothing logged: there is nothing to count from.
        assertEquals(
            NexCycleToday.Phase.EMPTY,
            NexCycleToday.of(ready(null), LocalDate.of(2026, 11, 14)).phase,
        )
        // A start date in the future (a clock rolled back, a date typo)
        // must not report a negative day.
        assertEquals(
            NexCycleToday.Phase.EMPTY,
            NexCycleToday.of(ready(LocalDate.of(2026, 11, 20)), LocalDate.of(2026, 11, 14)).phase,
        )
    }

    @Test
    fun anOpenPeriodCountsFromDayOne() {
        val today = NexCycleToday.of(ready(LocalDate.of(2026, 11, 14)), LocalDate.of(2026, 11, 14))
        assertEquals(NexCycleToday.Phase.PERIOD, today.phase)
        assertEquals(1, today.cycleDay)
    }

    @Test
    fun aClosedPeriodStillReportsItsOwnDays() {
        val today = NexCycleToday.of(
            ready(LocalDate.of(2026, 11, 1), periodEnd = LocalDate.of(2026, 11, 5)),
            LocalDate.of(2026, 11, 3),
        )
        assertEquals(NexCycleToday.Phase.PERIOD, today.phase)
        assertEquals(3, today.cycleDay)
    }

    @Test
    fun insideTheFertileWindowIsFertileAndOvulationCountsDown() {
        // Day 14 of a 28-day cycle from Nov 1: the window runs Nov 12–17,
        // and the likely ovulation lands Nov 15 — one day out.
        val start = LocalDate.of(2026, 11, 1)
        val today = NexCycleToday.of(
            ready(start, periodEnd = pastPeriod(start)),
            LocalDate.of(2026, 11, 14),
        )
        assertEquals(NexCycleToday.Phase.FERTILE, today.phase)
        assertEquals(14, today.cycleDay)
        assertEquals(1, today.ovulationIn)
    }

    @Test
    fun threeDaysOutIsSoon() {
        // Next start Nov 29; three days out is Nov 26.
        val start = LocalDate.of(2026, 11, 1)
        val today = NexCycleToday.of(
            ready(start, periodEnd = pastPeriod(start)),
            LocalDate.of(2026, 11, 26),
        )
        assertEquals(NexCycleToday.Phase.SOON, today.phase)
        assertEquals(3, today.daysUntil)
    }

    @Test
    fun theQuietMiddleIsCalmAndCarriesTheLength() {
        val start = LocalDate.of(2026, 11, 1)
        val today = NexCycleToday.of(
            ready(start, periodEnd = pastPeriod(start)),
            LocalDate.of(2026, 11, 19),
        )
        assertEquals(NexCycleToday.Phase.CALM, today.phase)
        assertEquals(19, today.cycleDay)
        assertEquals(28, today.cycleLength)
        // The pearl sits just past halfway round a 28-day ring on day 19.
        assertEquals(0.66f, today.progress, 0.01f)
    }

    @Test
    fun aMissedPredictionIsLateByWholeDays() {
        val start = LocalDate.of(2026, 11, 1)
        val today = NexCycleToday.of(
            ready(start, periodEnd = pastPeriod(start)),
            LocalDate.of(2026, 12, 5),
        )
        assertEquals(NexCycleToday.Phase.LATE, today.phase)
        assertEquals(-6, today.daysUntil)
    }

    @Test
    fun withoutAveragesThereIsNothingToPredictFrom() {
        // Breastfeeding, menopause, or the first cycle: no average means
        // the widget reports the period and otherwise stays quiet.
        val period = NexCycleToday.of(
            ready(LocalDate.of(2026, 11, 1), averageCycle = null, nextStart = null),
            LocalDate.of(2026, 11, 3),
        )
        assertEquals(NexCycleToday.Phase.PERIOD, period.phase)
        val quiet = NexCycleToday.of(
            ready(LocalDate.of(2026, 11, 1), periodEnd = LocalDate.of(2026, 11, 5), averageCycle = null, nextStart = null),
            LocalDate.of(2026, 11, 10),
        )
        assertEquals(NexCycleToday.Phase.QUIET, quiet.phase)
    }

    @Test
    fun pregnancyCountsWeeksDaysAndTheRoadLeft() {
        // 105 days from Aug 1 is exactly fifteen weeks; 280 − 105 remain.
        val today = NexCycleToday.of(
            ready(null, pregnancyStart = LocalDate.of(2026, 8, 1), mode = "pregnant"),
            LocalDate.of(2026, 11, 14),
        )
        assertEquals(NexCycleToday.Phase.PREGNANT, today.phase)
        assertEquals(15, today.pregnancyWeeks)
        assertEquals(0, today.pregnancyDays)
        assertEquals(175, today.pregnancyToGo)
        assertEquals(0.375f, today.progress, 0.001f)
    }
}
