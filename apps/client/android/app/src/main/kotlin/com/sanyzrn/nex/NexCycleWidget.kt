package com.sanyzrn.nex

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SweepGradient
import android.graphics.Typeface
import org.json.JSONObject
import java.io.File
import java.time.LocalDate
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * What the two «Cycle» widgets read: `nex_cycle_widget.json`, written by the
 * Dart side (`lib/platform/cycle_widget.dart`) beside the notes snapshot and
 * by the same app-lock rule — locked, the file says so and holds nothing else.
 *
 * Dates rather than sentences. Every count on the widget ("12 days until
 * your period") is worked out here from today's date, so it is right on the
 * days the app is not opened: the providers ask Android to wake them every
 * few hours, and a number baked into the file would be yesterday's by
 * morning.
 */
data class NexCycleSnapshot(
    val state: String,
    val mode: String,
    val lastStart: LocalDate?,
    val periodEnd: LocalDate?,
    val averageCycle: Int?,
    val averagePeriod: Int?,
    val nextStart: LocalDate?,
    val fertileStart: LocalDate?,
    val fertileEnd: LocalDate?,
    val ovulation: LocalDate?,
    val pregnancyStart: LocalDate?,
) {
    companion object {
        const val FILE_NAME = "nex_cycle_widget.json"
        const val SCHEMA_VERSION = 1

        fun read(context: Context): NexCycleSnapshot? = try {
            val file = File(context.filesDir, FILE_NAME)
            if (file.isFile) parse(file.readText()) else null
        } catch (_: Exception) {
            null
        }

        internal fun parse(json: String): NexCycleSnapshot? = try {
            val root = JSONObject(json)
            val version = root.optInt("version")
            if (version < 1 || version > SCHEMA_VERSION) {
                null
            } else {
                fun date(key: String): LocalDate? =
                    root.optString(key, "").takeIf { it.length == 10 }?.let {
                        runCatching { LocalDate.parse(it) }.getOrNull()
                    }
                fun int(key: String): Int? =
                    if (root.has(key)) root.optInt(key).takeIf { it > 0 } else null
                NexCycleSnapshot(
                    state = root.optString("state", "off"),
                    mode = root.optString("mode", "normal"),
                    lastStart = date("lastStart"),
                    periodEnd = date("periodEnd"),
                    averageCycle = int("averageCycle"),
                    averagePeriod = int("averagePeriod"),
                    nextStart = date("nextStart"),
                    fertileStart = date("fertileStart"),
                    fertileEnd = date("fertileEnd"),
                    ovulation = date("ovulation"),
                    pregnancyStart = date("pregnancyStart"),
                )
            }
        } catch (_: Exception) {
            null
        }
    }
}

/** Where the cycle is today, worked out from a [NexCycleSnapshot]. */
data class NexCycleToday(
    val phase: Phase,
    /** Day of the cycle, 1 on the first day of the last period. */
    val cycleDay: Int = 0,
    /** Days until the next period is expected; negative once it is late. */
    val daysUntil: Int = 0,
    val cycleLength: Int = 0,
    /** Days until likely ovulation, when it is still ahead. */
    val ovulationIn: Int? = null,
    /** Days until the fertile window opens, when it is still ahead. */
    val fertileIn: Int? = null,
    val pregnancyWeeks: Int = 0,
    val pregnancyDays: Int = 0,
    val pregnancyToGo: Int = 0,
    // Where things sit on the ring, 0–1 round from the top.
    val progress: Float = 0f,
    val periodFraction: Float = 0f,
    val fertileFrom: Float = 0f,
    val fertileTo: Float = 0f,
) {
    enum class Phase { OFF, SETUP, LOCKED, EMPTY, QUIET, PERIOD, FERTILE, SOON, CALM, LATE, PREGNANT }

    companion object {
        fun of(snapshot: NexCycleSnapshot?, today: LocalDate): NexCycleToday {
            val s = snapshot ?: return NexCycleToday(Phase.OFF)
            when (s.state) {
                "locked" -> return NexCycleToday(Phase.LOCKED)
                "setup" -> return NexCycleToday(Phase.SETUP)
                "ready" -> Unit
                else -> return NexCycleToday(Phase.OFF)
            }
            if (s.mode == "pregnant" && s.pregnancyStart != null) {
                val days = ChronoUnit.DAYS.between(s.pregnancyStart, today).toInt().coerceAtLeast(0)
                return NexCycleToday(
                    Phase.PREGNANT,
                    pregnancyWeeks = days / 7,
                    pregnancyDays = days % 7,
                    pregnancyToGo = (280 - days).coerceAtLeast(0),
                    progress = (days / 280f).coerceIn(0f, 1f),
                    periodFraction = (days / 280f).coerceIn(0.02f, 1f),
                )
            }
            val start = s.lastStart ?: return NexCycleToday(Phase.EMPTY)
            val cycleDay = ChronoUnit.DAYS.between(start, today).toInt() + 1
            if (cycleDay < 1) return NexCycleToday(Phase.EMPTY)
            val inPeriod = if (s.periodEnd == null) true else !today.isAfter(s.periodEnd)
            val average = s.averageCycle
            val next = s.nextStart
            if (average == null || next == null) {
                // Breastfeeding, menopause, or nothing to predict from yet.
                return NexCycleToday(
                    if (inPeriod) Phase.PERIOD else Phase.QUIET,
                    cycleDay = cycleDay,
                )
            }
            val length = max(average, cycleDay)
            fun at(date: LocalDate?, plus: Int = 0): Float =
                if (date == null) 0f
                else (ChronoUnit.DAYS.between(start, date).toInt() + plus) / length.toFloat()
            val daysUntil = ChronoUnit.DAYS.between(today, next).toInt()
            val fertileNow = s.fertileStart != null && s.fertileEnd != null &&
                !today.isBefore(s.fertileStart) && !today.isAfter(s.fertileEnd)
            val phase = when {
                inPeriod -> Phase.PERIOD
                daysUntil < 0 -> Phase.LATE
                fertileNow -> Phase.FERTILE
                daysUntil <= 3 -> Phase.SOON
                else -> Phase.CALM
            }
            return NexCycleToday(
                phase = phase,
                cycleDay = cycleDay,
                daysUntil = daysUntil,
                cycleLength = average,
                ovulationIn = s.ovulation?.let {
                    ChronoUnit.DAYS.between(today, it).toInt().takeIf { d -> d >= 0 }
                },
                fertileIn = s.fertileStart?.let {
                    ChronoUnit.DAYS.between(today, it).toInt().takeIf { d -> d > 0 }
                },
                progress = ((cycleDay - 0.5f) / length).coerceIn(0f, 1f),
                periodFraction = ((s.averagePeriod ?: 5) / length.toFloat()).coerceIn(0.02f, 1f),
                fertileFrom = at(s.fertileStart),
                fertileTo = at(s.fertileEnd, 1),
            )
        }
    }
}

/** The look and the words both Cycle widgets share. */
object NexCycleWidget {

    fun night(context: Context): Boolean =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES

    /** A count in the widget's own digits — «۱۲» in Persian. */
    fun digits(context: Context, value: Int): String {
        val locale = context.resources.configuration.locales[0]
        val format = if (locale.language == "fa") Locale("fa", "IR") else locale
        return String.format(format, "%d", value)
    }

    /**
     * The ring, as a bitmap — RemoteViews cannot hold a custom view. The
     * period in rose fading to mauve, the fertile days in teal, a pearl for
     * today, each arc with a soft glow under it; and, for the discreet
     * widget, a number in the middle.
     */
    fun ring(context: Context, today: NexCycleToday, sizeDp: Int, center: String?): Bitmap {
        val density = context.resources.displayMetrics.density
        val size = (sizeDp * density).toInt().coerceAtLeast(48)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val dark = night(context)
        val rose = if (dark) 0xFFF28DA4.toInt() else 0xFFD9506F.toInt()
        val mauve = if (dark) 0xFFB99AE0.toInt() else 0xFFA26BB4.toInt()
        val teal = if (dark) 0xFF72D2BF.toInt() else 0xFF2E9C88.toInt()
        val track = if (dark) 0x1FFFFFFF else 0x14000000
        val stroke = size * 0.085f
        val inset = stroke * 1.4f
        val rect = RectF(inset, inset, size - inset, size - inset)
        val cx = size / 2f
        val cy = size / 2f

        canvas.drawArc(rect, 0f, 360f, false, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            color = track
        })

        fun arc(from: Float, sweep: Float, a: Int, b: Int) {
            if (sweep <= 0f) return
            val startDeg = -90f + 360f * from
            val sweepDeg = 360f * sweep
            val shader = SweepGradient(cx, cy, intArrayOf(a, b), floatArrayOf(0f, sweep.coerceIn(0.01f, 1f)))
            shader.setLocalMatrix(Matrix().apply { setRotate(startDeg, cx, cy) })
            val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke * 1.5f
                strokeCap = Paint.Cap.ROUND
                this.shader = shader
                alpha = 110
                maskFilter = BlurMaskFilter(stroke * 0.8f, BlurMaskFilter.Blur.NORMAL)
            }
            canvas.drawArc(rect, startDeg, sweepDeg, false, glow)
            canvas.drawArc(rect, startDeg, sweepDeg, false, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = stroke
                strokeCap = Paint.Cap.ROUND
                this.shader = shader
            })
        }

        val drawsRing = today.phase !in setOf(
            NexCycleToday.Phase.OFF, NexCycleToday.Phase.SETUP,
            NexCycleToday.Phase.LOCKED, NexCycleToday.Phase.EMPTY,
        )
        if (drawsRing) {
            arc(0f, today.periodFraction, rose, mauve)
            if (today.fertileTo > today.fertileFrom && today.fertileFrom >= 0f && today.fertileTo <= 1f) {
                arc(today.fertileFrom, today.fertileTo - today.fertileFrom, Color.argb(190, Color.red(teal), Color.green(teal), Color.blue(teal)), teal)
            }
            if (today.phase != NexCycleToday.Phase.QUIET) {
                val angle = Math.toRadians((-90.0 + 360.0 * today.progress))
                val r = rect.width() / 2f
                val x = cx + (r * cos(angle)).toFloat()
                val y = cy + (r * sin(angle)).toFloat()
                canvas.drawCircle(x, y, stroke * 1.2f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = rose
                    alpha = 120
                    maskFilter = BlurMaskFilter(stroke * 0.7f, BlurMaskFilter.Blur.NORMAL)
                })
                canvas.drawCircle(x, y, stroke * 0.72f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE })
                canvas.drawCircle(x, y, stroke * 0.36f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = rose })
            }
        }

        if (center != null) {
            val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = if (dark) 0xFFF6EEF3.toInt() else 0xFF3A2430.toInt()
                textSize = size * 0.28f
                textAlign = Paint.Align.CENTER
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            }
            canvas.drawText(center, cx, cy - (text.ascent() + text.descent()) / 2f, text)
        }
        return bitmap
    }

    /** Title, headline, the line under it and a kind word, for the full widget. */
    fun lines(context: Context, t: NexCycleToday): List<String> {
        val r = context.resources
        fun n(value: Int) = digits(context, value)
        fun q(id: Int, count: Int) = r.getQuantityString(id, count, n(count))
        val title = if (t.cycleDay > 0 && t.phase != NexCycleToday.Phase.PREGNANT) {
            r.getString(R.string.cycle_widget_title_day, n(t.cycleDay))
        } else {
            r.getString(R.string.cycle_widget_title)
        }
        val headline = when (t.phase) {
            NexCycleToday.Phase.OFF -> r.getString(R.string.cycle_widget_off)
            NexCycleToday.Phase.SETUP -> r.getString(R.string.cycle_widget_setup)
            NexCycleToday.Phase.LOCKED -> r.getString(R.string.cycle_widget_locked)
            NexCycleToday.Phase.EMPTY -> r.getString(R.string.cycle_widget_first)
            NexCycleToday.Phase.QUIET -> r.getString(R.string.cycle_widget_quiet)
            NexCycleToday.Phase.PERIOD -> r.getString(R.string.cycle_widget_period, n(t.cycleDay))
            NexCycleToday.Phase.FERTILE -> r.getString(R.string.cycle_widget_fertile)
            NexCycleToday.Phase.LATE -> q(R.plurals.cycle_widget_late, -t.daysUntil)
            NexCycleToday.Phase.PREGNANT ->
                r.getString(R.string.cycle_widget_pregnant, n(t.pregnancyWeeks), n(t.pregnancyDays))
            NexCycleToday.Phase.SOON, NexCycleToday.Phase.CALM -> when (t.daysUntil) {
                0 -> r.getString(R.string.cycle_widget_today)
                1 -> r.getString(R.string.cycle_widget_tomorrow)
                else -> q(R.plurals.cycle_widget_until, t.daysUntil)
            }
        }
        val sub = when (t.phase) {
            NexCycleToday.Phase.PREGNANT -> q(R.plurals.cycle_widget_to_go, t.pregnancyToGo)
            NexCycleToday.Phase.FERTILE -> when (val d = t.ovulationIn) {
                null -> ""
                0 -> r.getString(R.string.cycle_widget_ovulation_today)
                else -> q(R.plurals.cycle_widget_ovulation_in, d ?: 0)
            }
            NexCycleToday.Phase.CALM, NexCycleToday.Phase.SOON -> when (val d = t.fertileIn) {
                null -> r.getString(R.string.cycle_widget_of, n(t.cycleDay), n(t.cycleLength))
                else -> q(R.plurals.cycle_widget_fertile_in, d ?: 0)
            }
            else -> ""
        }
        val whisper = when (t.phase) {
            NexCycleToday.Phase.PERIOD -> r.getString(R.string.cycle_widget_whisper_period)
            NexCycleToday.Phase.FERTILE -> r.getString(R.string.cycle_widget_whisper_fertile)
            NexCycleToday.Phase.SOON -> r.getString(R.string.cycle_widget_whisper_soon)
            NexCycleToday.Phase.PREGNANT -> r.getString(R.string.cycle_widget_whisper_pregnant)
            NexCycleToday.Phase.CALM, NexCycleToday.Phase.LATE, NexCycleToday.Phase.QUIET ->
                r.getString(R.string.cycle_widget_whisper_calm)
            else -> ""
        }
        return listOf(title, headline, sub, whisper)
    }

    /** The one number the discreet widget shows, or a dot when there is none. */
    fun center(context: Context, t: NexCycleToday): String = when (t.phase) {
        NexCycleToday.Phase.PERIOD -> digits(context, t.cycleDay)
        NexCycleToday.Phase.FERTILE, NexCycleToday.Phase.SOON, NexCycleToday.Phase.CALM ->
            digits(context, t.daysUntil)
        NexCycleToday.Phase.LATE -> "+" + digits(context, -t.daysUntil)
        NexCycleToday.Phase.PREGNANT -> digits(context, t.pregnancyWeeks)
        else -> "·"
    }
}
