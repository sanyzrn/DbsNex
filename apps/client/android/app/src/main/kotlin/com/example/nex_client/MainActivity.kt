package com.example.nex_client

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Handles:
 * - Widget → text capture (FR-8.1)
 * - Share intent text / links / photos (FR-8.2)
 *
 * Same zero-mandatory-field, auto-save rules as in-app capture (FR-8.3).
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
        val path = copyUriToCache(data.data!!)
        pendingResult?.success(path)
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
                            val path = copyUriToCache(uri)
                            if (path != null) {
                                enqueue(mapOf("type" to "shared_photo", "path" to path))
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
                    val path = copyUriToCache(first)
                    if (path != null) {
                        enqueue(mapOf("type" to "shared_photo", "path" to path))
                    }
                }
            }
        }
    }

    private fun enqueue(payload: Map<String, Any?>) {
        pending = payload
        channel?.invokeMethod("onOsCapture", payload)
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            val out = File(dir, "share-${System.currentTimeMillis()}.bin")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(out).use { output -> input.copyTo(output) }
            }
            out.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        const val ACTION_TEXT_CAPTURE = "com.example.nex_client.TEXT_CAPTURE"
        private const val REQUEST_PICK_FILE = 9911
    }
}
