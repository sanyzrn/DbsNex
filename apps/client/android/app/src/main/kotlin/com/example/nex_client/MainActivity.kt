package com.example.nex_client

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Handles:
 * - Widget → text capture (FR-8.1)
 * - Share intent text / links / photos / files (FR-8.2)
 *
 * Same zero-mandatory-field, auto-save rules as in-app capture (FR-8.3).
 * Preserves original display name + MIME when copying shared/picked URIs.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "nex/os_capture"
    private var channel: MethodChannel? = null
    private var pending: Map<String, Any?>? = null
    private var filePickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "takePending" -> {
                    val payload = pending
                    pending = null
                    result.success(payload)
                }
                "pickFile" -> {
                    filePickResult = result
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = "*/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    startActivityForResult(intent, REQUEST_PICK_FILE)
                }
                else -> result.notImplemented()
            }
        }
        handleIncoming(intent)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PICK_FILE) return
        val pendingResult = filePickResult
        filePickResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            pendingResult?.success(null)
            return
        }
        pendingResult?.success(copyUriToCache(data.data!!))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncoming(intent)
    }

    private fun handleIncoming(intent: Intent?) {
        if (intent == null) return
        when {
            intent.action == ACTION_TEXT_CAPTURE -> {
                enqueue(mapOf("type" to "text_capture"))
            }
            intent.action == Intent.ACTION_SEND -> {
                val type = intent.type ?: ""
                when {
                    type.startsWith("text/") -> {
                        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                        if (!text.isNullOrBlank()) {
                            enqueue(mapOf("type" to "shared_text", "text" to text))
                        }
                    }
                    type.startsWith("image/") -> {
                        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                        if (uri != null) {
                            val copied = copyUriToCache(uri)
                            if (copied != null) {
                                enqueue(
                                    mapOf(
                                        "type" to "shared_photo",
                                        "path" to copied["path"],
                                        "filename" to copied["filename"],
                                        "mimeType" to copied["mimeType"],
                                    ),
                                )
                            }
                        }
                    }
                    else -> {
                        // Generic file share (FR-8.2) — preserve name + MIME.
                        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                        if (uri != null) {
                            val copied = copyUriToCache(uri)
                            if (copied != null) {
                                enqueue(
                                    mapOf(
                                        "type" to "shared_file",
                                        "path" to copied["path"],
                                        "filename" to copied["filename"],
                                        "mimeType" to copied["mimeType"],
                                    ),
                                )
                            }
                        }
                    }
                }
            }
            intent.action == Intent.ACTION_SEND_MULTIPLE &&
                (intent.type?.startsWith("image/") == true) -> {
                @Suppress("UNCHECKED_CAST")
                val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                val first = uris?.firstOrNull()
                if (first != null) {
                    val copied = copyUriToCache(first)
                    if (copied != null) {
                        enqueue(
                            mapOf(
                                "type" to "shared_photo",
                                "path" to copied["path"],
                                "filename" to copied["filename"],
                                "mimeType" to copied["mimeType"],
                            ),
                        )
                    }
                }
            }
        }
    }

    private fun enqueue(payload: Map<String, Any?>) {
        pending = payload
        channel?.invokeMethod("onOsCapture", payload)
    }

    /**
     * Copy [uri] into app cache, preserving display name and MIME when resolvable.
     * Returns a map: path, filename, mimeType — never a opaque `.bin` placeholder alone.
     */
    private fun copyUriToCache(uri: Uri): Map<String, String?>? {
        return try {
            val mime = contentResolver.getType(uri)
                ?: intentMimeFallback()
            val displayName = queryDisplayName(uri)
                ?: defaultNameForMime(mime)
            val safeName = displayName.replace(Regex("[\\\\/]+"), "_")
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            // Unique prefix avoids collisions; keep original basename for Dart to read.
            val out = File(dir, "${System.currentTimeMillis()}-$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output -> input.copyTo(output) }
            } ?: return null
            mapOf(
                "path" to out.absolutePath,
                "filename" to displayName,
                "mimeType" to mime,
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun intentMimeFallback(): String? = intent?.type

    private fun queryDisplayName(uri: Uri): String? {
        var name: String? = null
        val cursor: Cursor? = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )
        cursor?.use {
            if (it.moveToFirst()) {
                val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) name = it.getString(idx)
            }
        }
        if (!name.isNullOrBlank()) return name
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
    }

    private fun defaultNameForMime(mime: String?): String {
        val ext = mime?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) }
            ?: "bin"
        return "shared-${System.currentTimeMillis()}.$ext"
    }

    companion object {
        const val ACTION_TEXT_CAPTURE = "com.example.nex_client.TEXT_CAPTURE"
        private const val REQUEST_PICK_FILE = 9911
    }
}
