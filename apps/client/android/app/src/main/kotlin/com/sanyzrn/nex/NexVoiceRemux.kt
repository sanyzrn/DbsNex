package com.sanyzrn.nex

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Repackages a recorded AAC stream (ADTS frames) as an `.m4a` (DATA-04).
 *
 * Voice is recorded as a stream of self-describing frames so that a process
 * killed mid-memo still leaves audio that plays; an `.m4a` written directly
 * is unplayable until the recorder stops, because its index goes at the end.
 * The library keeps `.m4a` — it is what the transcription providers take —
 * so the stream is repackaged once recording is over, or on the next launch
 * for one the app never got to finish. No re-encoding: the same AAC frames,
 * moved into a different box.
 */
object NexVoiceRemux {
    /** True when [to] was written; [from] is left for the caller. */
    fun remux(from: File, to: File): Boolean {
        val partial = File(to.path + ".partial")
        var extractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        var started = false
        try {
            extractor = MediaExtractor().apply { setDataSource(from.path) }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: return false
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            muxer = MediaMuxer(partial.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val out = muxer.addTrack(format)
            muxer.start()
            started = true
            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()
            var samples = 0
            while (true) {
                info.size = extractor.readSampleData(buffer, 0)
                if (info.size < 0) break
                info.offset = 0
                info.presentationTimeUs = extractor.sampleTime
                info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
                muxer.writeSampleData(out, buffer, info)
                samples++
                extractor.advance()
            }
            muxer.stop()
            started = false
            if (samples == 0 || !partial.renameTo(to)) return false
            return true
        } catch (_: Exception) {
            return false
        } finally {
            runCatching { if (started) muxer?.stop() }
            runCatching { muxer?.release() }
            runCatching { extractor?.release() }
            partial.delete()
        }
    }
}
