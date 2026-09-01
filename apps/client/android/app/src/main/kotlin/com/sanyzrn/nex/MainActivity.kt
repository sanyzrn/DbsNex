package com.sanyzrn.nex

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
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
            "pdfPreview" -> result.success(
                renderPdfPreview(
                    call.argument<String>("path"),
                    call.argument<Int>("width") ?: 1200,
                    call.argument<Int>("maxHeight") ?: 960,
                )
            )
            "shareText" -> {
                startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text").orEmpty())
                }, null))
                result.success(null)
            }
            else -> result.notImplemented()
        }}
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
    // Which extra is present decides text vs. file, not the MIME type: a file
    // manager sharing a .md (or any other text-based) file sends
    // ACTION_SEND with type="text/markdown" and the file in EXTRA_STREAM —
    // matching the old `type.startsWith("text/")` check just as a genuine
    // plain-text share does, but with no EXTRA_TEXT at all. That branch's
    // `getStringExtra(EXTRA_TEXT)` came back null, `?.let` never ran, and the
    // share vanished with nothing captured and no error.
    private fun handleIncoming(intent: Intent?, live: Boolean) {
        if (intent?.action == ACTION_TEXT_CAPTURE) {
            return enqueue(mapOf("type" to "text_capture"), live)
        }
        if (intent?.action != Intent.ACTION_SEND) return
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
        pending = value
        if (live) channel?.invokeMethod("onOsCapture", value)
    }

    /**
     * The first page of a PDF as PNG bytes, or null when there is nothing to
     * show.
     *
     * No library for this on purpose. Android has rendered PDFs itself since
     * API 21 and this app's minimum is 24, while every Flutter PDF package
     * ships its own copy of PDFium — several megabytes added to the APK to do
     * what the platform already does. The trade is that this is Android only;
     * the Dart side treats a missing channel as "no preview here" and the file
     * row above it is unchanged either way.
     *
     * Rendered onto white first. A PDF page is paper: transparent wherever
     * nothing was drawn, which under a dark theme would come out as black text
     * on a black page.
     */
    private fun renderPdfPreview(path: String?, width: Int, maxHeight: Int): ByteArray? {
        if (path.isNullOrEmpty()) return null
        val file = File(path)
        if (!file.isFile) return null
        val target = width.coerceIn(200, 2400)
        val cap = maxHeight.coerceIn(200, 4800)
        var descriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        var page: PdfRenderer.Page? = null
        var bitmap: Bitmap? = null
        return try {
            descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(descriptor)
            if (renderer.pageCount < 1) return null
            page = renderer.openPage(0)
            if (page.width < 1 || page.height < 1) return null
            // Only the band the caller is going to show, not the whole page.
            // A full A4 at this width is around 1200x1700, and a bitmap is
            // four bytes a pixel — eight megabytes to draw a thumbnail, on
            // devices that have better uses for them. The scale is the page's
            // own; the bitmap is simply shorter than the page, so what lands
            // in it is the top of it at the right size.
            val scale = target.toFloat() / page.width
            val full = (page.height * scale).toInt().coerceAtLeast(1)
            bitmap = Bitmap.createBitmap(target, minOf(full, cap), Bitmap.Config.ARGB_8888)
            Canvas(bitmap).drawColor(Color.WHITE)
            page.render(
                bitmap,
                null,
                Matrix().apply { setScale(scale, scale) },
                PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY,
            )
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        } catch (_: Exception) {
            // A file that is not a PDF, one that is encrypted, one Android's
            // own renderer will not open. The caller shows the file row and
            // says nothing about a preview, which is what it did before.
            null
        } finally {
            // Order matters — a renderer closed with a page still open throws
            // — and each close is guarded because a failure while cleaning up
            // must not become the answer to "can this file be previewed".
            bitmap?.recycle()
            runCatching { page?.close() }
            runCatching { renderer?.close() }
            runCatching { descriptor?.close() }
        }
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
