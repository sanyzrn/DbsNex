package com.sanyzrn.nex

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** One note row the widgets can show. */
data class WidgetNote(
    val id: String,
    val type: String,
    val text: String,
    val timestampMillis: Long,
    val pinned: Boolean,
)

/**
 * Reads the widget snapshot JSON the Flutter side writes after every
 * timeline refresh (see `platform/widget_snapshot.dart` in the client).
 *
 * The file lives in the app's own files directory, which the widget
 * providers — same package, same process — can read without any permission.
 * Everything here fails open: a missing, stale or malformed snapshot simply
 * renders as an empty widget.
 */
object WidgetSnapshot {
    const val FILE_NAME = "widget_snapshot.json"

    fun read(context: Context): List<WidgetNote> {
        val file = File(context.filesDir, FILE_NAME)
        if (!file.exists()) return emptyList()
        return try {
            val root = JSONObject(file.readText())
            val notes = root.optJSONArray("notes") ?: JSONArray()
            buildList {
                for (i in 0 until notes.length()) {
                    val item = notes.optJSONObject(i) ?: continue
                    add(
                        WidgetNote(
                            id = item.optString("id"),
                            type = item.optString("type", "text"),
                            text = item.optString("text"),
                            timestampMillis = item.optLong("ts", 0L),
                            pinned = item.optBoolean("pinned", false),
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
