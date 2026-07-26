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
    private var pending: Map<String, String>? = null
    private var picker: MethodChannel.Result? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "nex/os_capture")
        channel?.setMethodCallHandler { call, result -> when (call.method) {
            "takePending" -> { result.success(pending); pending = null }
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
        handleIncoming(intent)
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
        super.onNewIntent(intent); setIntent(intent); handleIncoming(intent)
    }

    private fun handleIncoming(intent: Intent?) {
        if (intent?.action == ACTION_TEXT_CAPTURE) return enqueue(mapOf("type" to "text_capture"))
        if (intent?.action != Intent.ACTION_SEND) return
        val type = intent.type.orEmpty()
        if (type.startsWith("text/")) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.takeIf { it.isNotBlank() }?.let {
                enqueue(mapOf("type" to "shared_text", "text" to it))
            }
        } else intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uri ->
            copyUri(uri)?.let { data ->
                enqueue(data + ("type" to if (type.startsWith("image/")) "shared_photo" else "shared_file"))
            }
        }
    }

    private fun enqueue(value: Map<String, String>) {
        pending = value; channel?.invokeMethod("onOsCapture", value)
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

    companion object { const val ACTION_TEXT_CAPTURE = "com.sanyzrn.nex.TEXT_CAPTURE" }
}