package com.sanyzrn.nex

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null
    private var picker: MethodChannel.Result? = null

    /**
     * Where the two preview renderers run.
     *
     * A MethodChannel handler is invoked on the platform's main thread, and
     * both of these open a file, decode it, scale it and compress the result:
     * a 4K frame or a dense PDF page is tens of milliseconds at best and well
     * past the ANR threshold at worst, all of it on the thread that draws the
     * app. Dart already awaits the answer, so nothing about the call's shape
     * changes by moving the work off it.
     *
     * One thread, not a pool: each of these holds a full-size bitmap, and two
     * at once is two of them.
     */
    private val renderExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nex-preview").apply { isDaemon = true }
    }

    /**
     * Where a shared or picked file is copied out of its content provider.
     *
     * Its own thread rather than [renderExecutor]'s, because the reason that
     * one is single-threaded is bitmap memory, and a file copy holds none. On
     * a shared executor a one-gigabyte video would sit in front of every
     * thumbnail the timeline wanted to draw while it copied.
     */
    private val ioExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nex-io").apply { isDaemon = true }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Runs [work] off the main thread and answers [result] back on it.
     *
     * A `MethodChannel.Result` may only be used from the main thread, and a
     * failure inside [work] is an absence rather than an error: every caller
     * on the Dart side treats null as "no preview here" already.
     */
    private fun <T> replyAsync(
        result: MethodChannel.Result,
        executor: ExecutorService = renderExecutor,
        work: () -> T?,
    ) {
        executor.execute {
            val value = runCatching(work).getOrNull()
            mainHandler.post {
                // The engine can be gone by now — the sheet that asked was
                // closed, or the Activity was recreated. Answering a result
                // nobody is listening to throws rather than being ignored.
                runCatching { result.success(value) }
            }
        }
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "nex/os_capture")
        channel?.setMethodCallHandler { call, result -> when (call.method) {
            "takePending" -> { result.success(pending); pending = null }
            // Whether the OS may capture what this window is showing.
            //
            // FLAG_SECURE is the only thing that blanks the recents thumbnail
            // and refuses a screenshot; there is no Flutter-side equivalent,
            // because the frame the system grabs is taken outside the app.
            // Set from Dart because the app lock it follows is a preference
            // Dart owns, and re-applied whenever that preference changes.
            //
            // Handlers run on the main thread, which is where a window flag
            // has to be set, so no hop is needed here.
            "setSecure" -> {
                if (call.argument<Boolean>("on") == true) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            "pickFile" -> {
                picker = result
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "*/*"; addCategory(Intent.CATEGORY_OPENABLE)
                }, 9911)
            }
            "pdfPreview" -> {
                // Arguments are read here, on the main thread, so the call
                // object is never touched from the render thread.
                val path = call.argument<String>("path")
                val width = call.argument<Int>("width") ?: 1200
                val maxHeight = call.argument<Int>("maxHeight") ?: 960
                replyAsync(result) { renderPdfPreview(path, width, maxHeight) }
            }
            "videoPreview" -> {
                val path = call.argument<String>("path")
                val width = call.argument<Int>("width") ?: 1080
                replyAsync(result) { renderVideoPoster(path, width) }
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
        handleIncoming(intent, live = false)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 9911) return
        val result = picker.also { picker = null } ?: return
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // The copy, not the answer, is what took the time. `copyUri` opens the
        // provider's stream and writes the whole file through to the cache —
        // seconds for a video, on the thread that draws the app, with Dart
        // awaiting the result anyway. Picking a large file froze the app until
        // the copy finished, and past five seconds that is the system's
        // "Nex isn't responding" dialog.
        replyAsync(result, ioExecutor) { copyUri(uri) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent); handleIncoming(intent, live = true)
    }

    override fun onDestroy() {
        // This Activity is recreated on a configuration change, and each one
        // brings its own executor. Without this, every rotation leaves a
        // parked thread behind. `shutdown`, not `shutdownNow`: work already
        // running finishes and posts its answer, which the reply guards
        // against a channel that has gone.
        renderExecutor.shutdown()
        ioExecutor.shutdown()
        super.onDestroy()
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
            return
        }

        val type = intent.type.orEmpty()
        val labelled = { data: Map<String, String> ->
            data + ("type" to if (type.startsWith("image/")) "shared_photo" else "shared_file")
        }

        // [live] decides the thread as well as the delivery, and the reason is
        // the same in both halves: what is already running.
        //
        // A share into a running app arrives on `onNewIntent`, with a window
        // drawing and taking input. Copying a gigabyte there is the classic
        // ANR — five seconds of an app that was responding a moment ago —
        // so it goes to [ioExecutor] and comes back to the main thread to
        // enqueue, because `pending` and `channel.invokeMethod` may only be
        // touched there.
        //
        // The cold-start half stays synchronous, deliberately. It runs inside
        // `configureFlutterEngine`, before there is a window accepting input
        // at all, so there is nothing to stop responding — the cost is a
        // slower launch, not a dialog. And the ordering is load-bearing:
        // `pending` has to be set before Dart's `start()` calls `takePending`,
        // which happens moments later. Copying off-thread there would let
        // `takePending` return null and drop the share entirely, since
        // `live = false` means nothing is pushed to catch it.
        if (live) {
            ioExecutor.execute {
                val data = copyUri(stream) ?: return@execute
                mainHandler.post { enqueue(labelled(data), true) }
            }
        } else {
            copyUri(stream)?.let { enqueue(labelled(it), false) }
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

    /**
     * A frame of a video as JPEG bytes, or null when there is nothing to show.
     *
     * JPEG, unlike the PDF above, and the difference is the content rather
     * than a preference. A rendered page is mostly flat white with sharp
     * text, which is what PNG is good at; a frame of video is a photograph,
     * which is what it is worst at. The same 1080-wide frame is a few hundred
     * kilobytes as JPEG and several megabytes as PNG — and every one of those
     * bytes is copied across the method channel to be drawn at thumbnail
     * size.
     *
     * No library for this either, and for the same reason as the PDF above:
     * Android has pulled frames out of video since long before this app's
     * minimum, and the alternative is a codec plugin and a render surface to
     * produce one still picture.
     *
     * Which frame is a judgement, not an obvious answer. The very first is
     * what "cover" sounds like and is frequently black — a lot of video fades
     * in, and a phone camera's first frame is whatever the sensor had before
     * it settled. So this asks for one second in, which is past the fade on
     * nearly everything — except on a clip under two seconds, where a second
     * in may be the end of it, and the first frame is all there is.
     *
     * OPTION_CLOSEST_SYNC, not OPTION_CLOSEST: the former returns a keyframe
     * near the requested time, which is a decode; the latter walks forward
     * frame by frame to land exactly, which on a long video is a visible
     * stall for a picture nobody asked to be exact.
     */
    private fun renderVideoPoster(path: String?, width: Int): ByteArray? {
        if (path.isNullOrEmpty()) return null
        val file = File(path)
        if (!file.isFile) return null
        val target = width.coerceIn(120, 2160)
        val retriever = MediaMetadataRetriever()
        var frame: Bitmap? = null
        var scaled: Bitmap? = null
        return try {
            retriever.setDataSource(file.absolutePath)
            val durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            val atUs = if (durationMs > 2_000L) 1_000_000L else 0L
            // The fallback is the first frame — black beats nothing, and a
            // clip whose keyframe layout defeats the seek still has one.
            val decoded = retriever.frameAt(atUs, target)
                ?: retriever.frameAt(0L, target)
                ?: return null
            frame = decoded
            // getScaledFrameAtTime already sized it; getFrameAtTime did not,
            // and a 4K frame is thirty-three megabytes of bitmap to hand
            // across the channel for something drawn at thumbnail size.
            val poster = if (decoded.width > target) {
                val height = (decoded.height.toLong() * target / decoded.width)
                    .toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(decoded, target, height, true)
            } else {
                decoded
            }
            scaled = poster
            val out = ByteArrayOutputStream()
            // 85: the point on this curve where a still frame shown at
            // thumbnail size stops looking any better and the file keeps
            // getting bigger.
            poster.compress(Bitmap.CompressFormat.JPEG, 85, out)
            out.toByteArray()
        } catch (_: Exception) {
            // A file that is not a video, one in a codec this device has no
            // decoder for, a download that stopped halfway. The caller shows
            // the file row and says nothing about a cover, which is what it
            // did before.
            null
        } finally {
            // `scaled` is `frame` itself whenever no scaling was needed, so
            // recycling both would recycle one twice.
            if (scaled !== frame) scaled?.recycle()
            frame?.recycle()
            runCatching { retriever.release() }
        }
    }

    /**
     * The frame at [atUs], asked for at [target] pixels wide where the
     * platform can do the scaling itself.
     *
     * getScaledFrameAtTime arrived in API 27 and decodes straight into a
     * bitmap of the size asked for. Below that there is only getFrameAtTime,
     * which allocates the frame at the video's own resolution and leaves the
     * resizing to the caller.
     */
    private fun MediaMetadataRetriever.frameAt(atUs: Long, target: Int): Bitmap? {
        val option = MediaMetadataRetriever.OPTION_CLOSEST_SYNC
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val width = extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
            )?.toIntOrNull() ?: 0
            val height = extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
            )?.toIntOrNull() ?: 0
            if (width < 1 || height < 1) {
                getFrameAtTime(atUs, option)
            } else {
                val scaledWidth = minOf(target, width)
                val scaledHeight = (height.toLong() * scaledWidth / width)
                    .toInt().coerceAtLeast(1)
                getScaledFrameAtTime(atUs, option, scaledWidth, scaledHeight)
            }
        } else {
            getFrameAtTime(atUs, option)
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
