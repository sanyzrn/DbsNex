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
import android.widget.Toast
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

open class MainActivity : FlutterFragmentActivity() {
    /**
     * Whether this window exists only to receive a share, and should take
     * itself down once one has been captured.
     *
     * False here: the launcher's own Activity is where the app lives, and a
     * share that lands on it (an in-app pick, a widget tap) leaves it open.
     * [ShareActivity] overrides it.
     */
    protected open val closesAfterShare = false

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
            // Fetch the file a share referred to, now that Dart has decided
            // it is worth having. Split from the share itself so that a file
            // over the limit costs a metadata query instead of a full copy.
            //
            // The read grant on a shared URI belongs to this Activity's task
            // and outlives the intent that carried it, so re-parsing the
            // string Dart was given reaches the same file. Off the main
            // thread: this is the copy, and it is the slow part.
            "copyShared" -> {
                val uri = call.argument<String>("uri")
                replyAsync(result, ioExecutor) {
                    uri?.let { copyUri(Uri.parse(it))?.get("path") }
                }
            }
            // Which kind of window this is, asked before anything is drawn.
            // `NexBootstrapHost` paints nothing at all when the answer is
            // true, which is what keeps a share from flashing Nex over the
            // app the person was using.
            "isShareWindow" -> result.success(closesAfterShare)
            // Say what happened to the share, and close the window if this is
            // the one that only existed to receive it.
            //
            // A toast rather than anything in the app, because by design
            // there is no app on screen to put it in — and because it has to
            // outlive this Activity by a couple of seconds. The text comes
            // from Dart: the app's language is a preference, and the platform
            // only knows the device's.
            "shareDone" -> {
                val message = call.argument<String>("message")
                if (!message.isNullOrBlank()) {
                    Toast.makeText(applicationContext, message, Toast.LENGTH_LONG).show()
                }
                // Answered before the window goes, so the reply cannot race
                // the engine being torn down with Dart still awaiting it.
                result.success(closesAfterShare)
                // `finish`, never `finishAndRemoveTask`: this Activity is
                // sitting in the *sharing* app's task, so removing the task
                // would close the app the person shared from.
                if (closesAfterShare) finish()
            }
            // Put the download in the shade, and keep the process alive
            // while it runs — see [DownloadService].
            //
            // Answers whether the platform took the job, because the Dart
            // side falls back to its own progress notification where there is
            // no service to run (Windows, where nothing suspends the process
            // and an ordinary notification was always enough).
            //
            // Started only while the service is down. Android 12 refuses to
            // start a foreground service from the background, and every
            // progress update after the first arrives from the background by
            // definition — that is the situation the service exists for — so
            // the rest only rewrite the notification, which nothing
            // restricts. A refused start is caught rather than fatal: the
            // worst case is the old behaviour.
            "downloadNotice" -> {
                val title = call.argument<String>("title").orEmpty()
                val percent = call.argument<Int>("percent") ?: 0
                if (DownloadService.running) {
                    DownloadService.update(this, title, percent)
                    result.success(true)
                } else {
                    val intent = Intent(this, DownloadService::class.java)
                        .putExtra(DownloadService.EXTRA_TITLE, title)
                        .putExtra(DownloadService.EXTRA_PERCENT, percent)
                    val started = runCatching {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    }.isSuccess
                    result.success(started)
                }
            }
            "stopDownloadNotice" -> {
                runCatching { stopService(Intent(this, DownloadService::class.java)) }
                result.success(true)
            }
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

        // Nothing is copied here, on either path. What goes across is what
        // the provider will say about the file — see [describeUri] — and Dart
        // asks for the copy with `copyShared` once it has decided to keep it.
        //
        // The copy used to happen right here, and it was the whole cost of a
        // share. A two-gigabyte video was written through to the cache before
        // Dart was told the first thing about it, and only then measured and
        // refused: minutes of work to produce a message saying the work should
        // never have started. On the cold-start path it was worse than slow —
        // it ran inside `configureFlutterEngine`, so the launch that was
        // supposed to be showing a note sat on the splash screen until the
        // copy finished.
        //
        // The ordering that used to make this delicate is now free: `pending`
        // has to be set before Dart's `start()` calls `takePending` moments
        // later, and a metadata query is fast enough that the synchronous
        // path costs nothing.
        enqueue(labelled(describeUri(stream)), live)
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

    /**
     * Everything about a shared file that can be known without reading it.
     *
     * This is what a share now sends across, in place of a path to a copy
     * that had already been made. The size is the point of it: it is the one
     * fact that decides whether the file is worth copying at all, and asking
     * the provider for it is a cursor query rather than a transfer.
     *
     * [sizeOf] answers -1 when a provider will not say, which some do not.
     * Dart treats that as "measure it after copying", which is what it had to
     * do for every file before this existed.
     */
    private fun describeUri(uri: Uri): Map<String, String> = mapOf(
        "uri" to uri.toString(),
        "filename" to (displayName(uri) ?: "shared-${System.currentTimeMillis()}"),
        "mimeType" to (contentResolver.getType(uri) ?: "application/octet-stream"),
        "size" to sizeOf(uri).toString(),
    )

    /** The provider's own byte count, or -1 when it will not give one. */
    private fun sizeOf(uri: Uri): Long {
        runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use {
                if (it.moveToFirst() && !it.isNull(0)) return it.getLong(0)
            }
        }
        // Not every provider backs the OpenableColumns cursor. A descriptor
        // does not read the file either, and answers for most of the rest.
        return runCatching {
            contentResolver.openAssetFileDescriptor(uri, "r")?.use { it.length }
        }.getOrNull() ?: -1L
    }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return uri.lastPathSegment
    }

    companion object { const val ACTION_TEXT_CAPTURE = "com.sanyzrn.nex.TEXT_CAPTURE" }
}
