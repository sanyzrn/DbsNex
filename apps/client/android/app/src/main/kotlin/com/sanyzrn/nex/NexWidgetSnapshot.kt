package com.sanyzrn.nex

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

/**
 * The denormalized snapshot the Dart side writes for the home-screen widgets.
 *
 * The widget never reads the library database. SQLite belongs to Dart (it is
 * opened inside a worker isolate there), and a second reader — especially one
 * running in a different process boundary with its own lifecycle — would turn
 * every schema change into a cross-language contract. Instead the app writes
 * one small JSON file: everything the widgets may show, and nothing else.
 *
 * The file lives in the app's private storage (`filesDir` — the same directory
 * `getApplicationSupportDirectory()` hands Dart, where `nex.sqlite` itself
 * sits). The widget provider runs inside the same APK and UID, so it can read
 * it directly; no other app can see it, and there is no content provider to
 * misconfigure. See the widget README for the full data contract.
 *
 * Privacy is enforced at write time, not at read time: when the app lock is
 * enabled the snapshot carries an empty note list, so note content never
 * reaches a file the home screen renders from. The reader below trusts the
 * file the way the widget trusts the app — it is the app that wrote it.
 *
 * The JSON is parsed with `org.json`, which is part of the platform: a notes
 * app does not need a JSON library on board to read four fields.
 */
data class NexWidgetSnapshot(
    val appLock: Boolean,
    val generatedAt: Long,
    val notes: List<NexWidgetNote>,
) {
    data class NexWidgetNote(
        val id: String,
        val type: String,
        val preview: String,
        val updatedAt: Long,
    )

    companion object {
        /** Bumped only when the field set changes in a way the reader must notice. */
        const val SCHEMA_VERSION = 1

        /** The snapshot file, or null when there is nothing to show yet. */
        fun read(context: Context): NexWidgetSnapshot? {
            return try {
                val file = File(context.filesDir, FILE_NAME)
                if (!file.isFile) return null
                parse(file.readText())
            } catch (_: Exception) {
                // A snapshot the app half wrote, or one a newer schema produced:
                // the widget shows its empty state rather than a broken frame.
                null
            }
        }

        internal fun parse(json: String): NexWidgetSnapshot? {
            return try {
                val root = JSONObject(json)
                if (root.optInt("version") != SCHEMA_VERSION) return null
                val appLock = root.optBoolean("appLock", false)
                val generatedAt = root.optLong("generatedAt", 0L)
                val rawNotes = root.optJSONArray("notes") ?: JSONArray()
                val notes = buildList {
                    for (i in 0 until rawNotes.length()) {
                        val note = rawNotes.optJSONObject(i) ?: continue
                        val id = note.optString("id")
                        if (id.isEmpty()) continue
                        add(
                            NexWidgetNote(
                                id = id,
                                type = note.optString("type", "text"),
                                preview = note.optString("preview"),
                                updatedAt = note.optLong("updatedAt", 0L),
                            )
                        )
                    }
                }
                NexWidgetSnapshot(appLock, generatedAt, notes)
            } catch (_: Exception) {
                null
            }
        }

        const val FILE_NAME = "nex_widget_snapshot.json"
    }
}

/**
 * Relative time in the widget's own words, using the same buckets the
 * timeline cards use (`nexRelativeTimeOf` in packages/ui): now, Xm, Xh, Xd,
 * Xw, Xmo, Xy — "الان", "۵ دقیقه قبل" and so on in Persian.
 *
 * Labels are Android string resources, so `values-fa` answers for Persian
 * without any of this code knowing about it. The count is formatted with the
 * resource's own locale so a Persian device reads "۵", not "5" — Java's
 * `%d` follows the locale it is handed, and `fa` without a region still
 * formats through Persian digits, but `fa_IR` is pinned anyway so the
 * choice does not drift with the device's country setting.
 *
 * Computed at render time, never stored: a label baked into the snapshot
 * would say "5m" for hours, because nothing wakes a widget to re-render it.
 * From the epoch in the file, every re-render (a data push, a resize, a
 * locale change) relabels honestly.
 */
object NexWidgetTime {

    fun label(context: Context, epochMs: Long, nowMs: Long): String {
        val resources = context.resources
        val locale = resources.configuration.locales[0]
        val formatLocale = if (locale.language == "fa") Locale("fa", "IR") else locale
        val minutes = ((nowMs - epochMs) / 60_000L).coerceAtLeast(0L)
        val (resource, count) = when {
            minutes < 1 -> return resources.getString(R.string.widget_time_now)
            minutes < 60 -> R.string.widget_time_minutes to minutes
            minutes < 60L * 24 -> R.string.widget_time_hours to minutes / 60
            minutes < 60L * 24 * 7 -> R.string.widget_time_days to minutes / (60 * 24)
            minutes < 60L * 24 * 30 -> R.string.widget_time_weeks to minutes / (60 * 24 * 7)
            minutes < 60L * 24 * 365 -> R.string.widget_time_months to minutes / (60 * 24 * 30)
            else -> R.string.widget_time_years to minutes / (60L * 24 * 365)
        }
        return String.format(formatLocale, resources.getString(resource), count)
    }
}
