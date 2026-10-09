package com.sanyzrn.nex

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.EmbeddingEngine
import com.google.ai.edge.litertlm.EmbeddingEngineConfig
import com.google.ai.edge.litertlm.EmbeddingOptions
import com.google.ai.edge.litertlm.InputData
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The on-device search model, EmbeddingGemma 2, on `nex/embedder`.
 *
 * LiteRT-LM's `EmbeddingEngine` (0.18.0 and later), not the chat `Engine`
 * the assistant's models run on: an embedding model answers nothing, it
 * turns text into a vector, and the chat engine has no way to ask it for
 * one. The Dart side (local_embedder.dart) puts EmbeddingGemma's own
 * prompts around the text before it gets here.
 *
 * Called from the database worker's isolate, where enrichment runs, as well
 * as from the install screen. Every call runs on one thread of its own, in
 * order: the engine is loaded once, on first use, and kept — loading is the
 * slow part — until [close] or a different model path.
 */
object NexEmbedder {
    private const val CHANNEL = "nex/embedder"

    private val worker = Executors.newSingleThreadExecutor { task ->
        Thread(task, "nex-embedder")
    }
    private val main = Handler(Looper.getMainLooper())

    // Only ever touched on [worker].
    private var engine: EmbeddingEngine? = null
    private var enginePath: String? = null

    /**
     * Released after this long unused (PERF-05), as the chat model is: it
     * used to stay in memory for the life of the process once loaded. The
     * next embed loads it again, in about a second.
     */
    private const val IDLE_MS = 3 * 60 * 1000L

    @Volatile
    private var lastUse = 0L

    private val idleClose = Runnable {
        worker.execute {
            if (SystemClock.uptimeMillis() - lastUse >= IDLE_MS) close()
        }
    }

    private fun touch() {
        lastUse = SystemClock.uptimeMillis()
        main.removeCallbacks(idleClose)
        main.postDelayed(idleClose, IDLE_MS)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val cacheDir = context.cacheDir.absolutePath
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "embed" -> {
                    val path = call.argument<String>("modelPath")
                    val texts = call.argument<List<String>>("texts")
                    if (path == null || texts == null) {
                        result.error("args", "modelPath and texts are required", null)
                    } else {
                        worker.execute {
                            // Throwable, not Exception: a runtime that will not
                            // load on this phone fails with an Error from its
                            // native half, and an unanswered call would leave
                            // the note's enrichment waiting forever.
                            val reply = runCatching { embed(path, texts, cacheDir) }
                            touch()
                            main.post {
                                reply.fold(
                                    onSuccess = { result.success(it) },
                                    onFailure = {
                                        result.error("embed", it.message ?: it.toString(), null)
                                    },
                                )
                            }
                        }
                    }
                }
                "release" -> worker.execute {
                    close()
                    main.post { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** One vector per text, L2-normalised, in the order given. */
    private fun embed(path: String, texts: List<String>, cacheDir: String): List<FloatArray> {
        val ready = engineFor(path, cacheDir)
        val inputs: List<List<InputData>> = texts.map { text -> listOf(InputData.Text(text)) }
        return ready
            .computeEmbeddingBatch(inputs, EmbeddingOptions(normalize = true))
            .map { response -> response.embedding }
    }

    private fun engineFor(path: String, cacheDir: String): EmbeddingEngine {
        val loaded = engine
        if (loaded != null && enginePath == path) return loaded
        close()
        require(File(path).isFile) { "No search model at $path" }
        val created = EmbeddingEngine(
            EmbeddingEngineConfig(
                modelPath = path,
                backend = Backend.CPU(),
                cacheDir = cacheDir,
            ),
        )
        created.initialize()
        engine = created
        enginePath = path
        return created
    }

    private fun close() {
        val loaded = engine ?: return
        engine = null
        enginePath = null
        runCatching { loaded.close() }
    }
}
