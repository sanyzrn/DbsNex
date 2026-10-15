package com.sanyzrn.nex

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.LocaleList
import android.widget.RemoteViews
import java.util.Locale
import kotlin.math.pow

/** Non-sensitive display preferences only; never reads the library. */
object NexWidgetAppearance {
    private const val STORE = "nex_widget_appearance"

    private fun luminance(color: Int): Double {
        fun linear(channel: Int): Double {
            val value = channel / 255.0
            return if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(Color.red(color)) +
            0.7152 * linear(Color.green(color)) + 0.0722 * linear(Color.blue(color))
    }

    fun foreground(color: Int): Int =
        if (luminance(color) > 0.179) Color.BLACK else Color.WHITE

    /** Always write the tint, even when restoring the drawable's own colours.
     * RemoteViews can reapply onto a launcher's existing ImageView. Omitting
     * the action then keeps yesterday's filter. Transparent SRC_ATOP is the
     * neutral operation, preserving the wordmark's separate letter/dot colours.
     */
    fun applyTint(views: RemoteViews, id: Int, color: Int?) {
        views.setInt(id, "setColorFilter", color ?: Color.TRANSPARENT)
    }

    /** Custom seeds need the same contrast protection as the in-app palette. */
    fun iconAccent(context: Context): Int? {
        val seed = accent(context) ?: return null
        val card = context.getColor(R.color.nex_widget_card)
        val overlay = context.getColor(R.color.nex_widget_action)
        fun mix(from: Int, to: Int, t: Double): Int = Color.rgb(
            (Color.red(from) + (Color.red(to) - Color.red(from)) * t).toInt(),
            (Color.green(from) + (Color.green(to) - Color.green(from)) * t).toInt(),
            (Color.blue(from) + (Color.blue(to) - Color.blue(from)) * t).toInt(),
        )
        val background = mix(card, overlay, Color.alpha(overlay) / 255.0)
        fun contrast(color: Int): Double {
            val a = luminance(color) + 0.05
            val b = luminance(background) + 0.05
            return maxOf(a, b) / minOf(a, b)
        }
        if (contrast(seed) >= 3.0) return seed
        val target = if (contrast(Color.WHITE) > contrast(Color.BLACK)) Color.WHITE else Color.BLACK
        for (step in 1..100) {
            val candidate = mix(seed, target, step / 100.0)
            if (contrast(candidate) >= 3.0) return candidate
        }
        return target
    }

    fun save(context: Context, locale: String?, accent: String?) {
        context.getSharedPreferences(STORE, Context.MODE_PRIVATE).edit()
            .putString("locale", locale).putString("accent", accent).apply()
    }

    fun localized(context: Context): Context {
        val language = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            .getString("locale", null)
        if (language != "fa" && language != "en") return context
        val config = Configuration(context.resources.configuration)
        val locale = Locale.forLanguageTag(language)
        config.setLocales(LocaleList(locale))
        config.setLayoutDirection(locale)
        return context.createConfigurationContext(config)
    }

    fun accent(context: Context): Int? {
        val value = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            .getString("accent", null) ?: return null
        if (!Regex("^#[0-9a-fA-F]{6}$").matches(value)) return null
        return Color.parseColor(value)
    }
}
