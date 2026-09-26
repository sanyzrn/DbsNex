package com.sanyzrn.nex

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.LocaleList
import java.util.Locale
import kotlin.math.pow

/** Non-sensitive display preferences only; never reads the library. */
object NexWidgetAppearance {
    private const val STORE = "nex_widget_appearance"

    fun foreground(color: Int): Int {
        fun linear(channel: Int): Double {
            val value = channel / 255.0
            return if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
        }
        val luminance = 0.2126 * linear(Color.red(color)) +
            0.7152 * linear(Color.green(color)) + 0.0722 * linear(Color.blue(color))
        return if (luminance > 0.179) Color.BLACK else Color.WHITE
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
