package com.sanyzrn.nex

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var widgetsChannel: MethodChannel? = null

    /// Deep links that arrived before the Flutter engine was ready are queued
    /// here, oldest first, and handed over when Dart calls `takePending`.
    /// The Flutter side turns each one into a capture or an open-note action.
    private val pending = ArrayDeque<Map<String, String>>()

    private var picker: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "nex/os_capture")
        channel?.setMethodCallHandler { call, result -> when (call.method) {
            // Everything that arrived before the engine was ready, oldest
            // first; the list is cleared so each event is delivered exactly
            // once, on whichever launch drained it.
            "takePending" -> {
                result.success(pending.toList().also { pending.clear() })
            }
            "pickFile" -> {
                picker = result
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                }, 9911)
            }
            "shareText" -> {
                startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text").orEmpty())
                }, null))
                result.success(null)
            }
            else -> result.notImplemented()
        }}

        // The Flutter side calls `refresh` after every timeline refresh; the
        // providers re-read the snapshot file and repaint every placed widget.
        widgetsChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "nex/widgets")
        widgetsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "refresh" -> {
                    NexWidgetProvider.refreshAll(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        handleIncoming(intent, live = false)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 9911) return
        val result = picker.also { picker = null }
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) result?.success(null)
        else result?.success(copyUri(uri))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent); handleIncoming(intent, live = true)
    }

    // [live] is false from configureFlutterEngine: that path always means a
    // fresh FlutterEngine, whose Dart side has not called start() yet, so an
    // immediate onOsCapture push either lands nowhere or gets buffered and
    // replayed once Dart does register a handler — right before its own
    // takePending() call retrieves the same still-set [pending] and the
    // capture lands twice. Queuing only and letting takePending() collect it
    // is the one delivery that path needs. onNewIntent, by contrast, fires on
    // an Activity/engine that is already running with Dart's handler already
    // registered and its one takePending() call long since made, so a live
    // push is the only way that event is ever delivered at all.
    //
    // Which extra is present decides text vs. file, not the MIME type: a file
    // manager sharing a .md (or any other text-based) file sends
    // ACTION_SEND with type="text/markdown" and the file in EXTRA_STREAM —
    // matching the old `type.startsWith("text/")` check just as a genuine
    // plain-text share does, but with no EXTRA_TEXT at all. That branch's
    // `getStringExtra(EXTRA_TEXT)` came back null, `?.let` never ran, and the
    // share vanished with nothing captured and no error.
    private fun handleIncoming(intent: Intent?, live: Boolean) {
        if (intent == null) return
        when (intent.action) {
            ACTION_TEXT_CAPTURE -> return enqueue(mapOf("type" to "text_capture"), live)
            ACTION_VOICE_CAPTURE -> return enqueue(mapOf("type" to "voice_capture"), live)
            ACTION_PHOTO_CAPTURE -> return enqueue(mapOf("type" to "camera_capture"), live)
            ACTION_OPEN_NOTE -> {
                val noteId = intent.getStringExtra(EXTRA_NOTE_ID)
                if (!noteId.isNullOrBlank()) {
                    return enqueue(mapOf("type" to "open_note", "noteId" to noteId), live)
                }
                return
            }
        }
        if (intent.action != Intent.ACTION_SEND) return
        val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (stream == null) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }?.let {
                enqueue(mapOf("type" to "shared_text", "text" to it), live)
            }
        } else copyUri(stream)?.let { data ->
            val type = intent.type.orEmpty()
            enqueue(
                data + ("type" to if (type.startsWith("image/")) "shared_photo" else "shared_file"),
                live,
            )
        }
    }

    private fun enqueue(value: Map<String, String>, live: Boolean) {
        pending.addLast(value)
        // A live push is delivered immediately; a cold-start event waits for
        // takePending() so it cannot be double-delivered.
        if (live) channel?.invokeMethod("onOsCapture", value)
    }

    private fun copyUri(uri: Uri): Map<String, String>? = try {
        val name = displayName(uri) ?: "shared-${System.currentTimeMillis()}"
        val safe = name.replace(Regex("[^A-Za-z0-9._ -]"), "_")
        val out = File(cacheDir, "shared").apply { mkdirs() }
            .resolve("${System.currentTimeMillis()}-$safe")
        contentResolver.openInputStream(uri)?.use { input ->
            FileOutputStream(out).use { output -> input.copyTo(output) }
        } ?: return null
        mapOf("path" to out.absolutePath, "filename" to name,
              "mimeType" to (contentResolver.getType(uri) ?: "application/octet-stream"))
    } catch (_: Exception) { null }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return uri.lastPathSegment
    }

    companion object {
        const val ACTION_TEXT_CAPTURE = "com.sanyzrn.nex.TEXT_CAPTURE"
        const val ACTION_VOICE_CAPTURE = "com.sanyzrn.nex.VOICE_CAPTURE"
        const val ACTION_PHOTO_CAPTURE = "com.sanyzrn.nex.PHOTO_CAPTURE"
        const val ACTION_OPEN_NOTE = "com.sanyzrn.nex.OPEN_NOTE"
        const val EXTRA_NOTE_ID = "note_id"
    }
}
