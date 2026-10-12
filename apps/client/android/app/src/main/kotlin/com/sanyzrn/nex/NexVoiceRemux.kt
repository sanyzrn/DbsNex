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
    /** An AAC-LC AudioSpecificConfig: what the stream's first frame holds. */
    private const val SETUP_BYTES = 2

    private val RATES = intArrayOf(
        96000, 88200, 64000, 48000, 44100, 32000, 24000,
        22050, 16000, 12000, 11025, 8000, 7350,
    )

    /**
     * True when [to] was written; [from] is left for the caller.
     *
     * The recorder's stream opens with the encoder's two-byte setup block —
     * its AudioSpecificConfig — framed as if it were audio. It is not audio,
     * and as the first sample of an `.m4a` some players decoded nothing at
     * all. It is also the one true account of what the encoder made: the
     * frame headers around it were written from what was asked of the
     * encoder, and on some phones that is not what it did. So the block is
     * not copied but used — as the track's own setup, with the sample rate
     * and channels it names — and the audio decodes as recorded.
     */
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
            val buffer = ByteBuffer.allocate(256 * 1024)
            val info = MediaCodec.BufferInfo()

            // The first sample: the setup block, or already audio.
            info.size = extractor.readSampleData(buffer, 0)
            if (info.size < 0) return false
            var pending = true
            if (info.size <= SETUP_BYTES) {
                val setup = ByteArray(info.size)
                buffer.position(0)
                buffer.get(setup)
                apply(setup, format)
                extractor.advance()
                pending = false
            }

            muxer = MediaMuxer(partial.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val out = muxer.addTrack(format)
            muxer.start()
            started = true
            var samples = 0
            while (true) {
                if (!pending) {
                    info.size = extractor.readSampleData(buffer, 0)
                    if (info.size < 0) break
                }
                pending = false
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

    /**
     * [path] as it plays: the file itself, or — for a voice note recorded
     * before 1.99.92, which still opens with the setup block and may carry
     * headers that disagree with it — a corrected copy in [cache], made once.
     * The stored file is never changed: its hash is what backups and sync
     * know it by.
     */
    fun playable(path: File, cache: File): File {
        if (!path.isFile || !opensWithSetup(path)) return path
        val folder = File(cache, "voice-playable").apply { mkdirs() }
        val copy = File(folder, path.nameWithoutExtension + "-" + path.length() + ".m4a")
        if (copy.isFile) return copy
        return if (remux(path, copy)) copy else path
    }

    private fun opensWithSetup(path: File): Boolean {
        var extractor: MediaExtractor? = null
        return try {
            extractor = MediaExtractor().apply { setDataSource(path.path) }
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: return false
            extractor.selectTrack(track)
            val size = extractor.readSampleData(ByteBuffer.allocate(256 * 1024), 0)
            size in 0..SETUP_BYTES
        } catch (_: Exception) {
            false
        } finally {
            runCatching { extractor?.release() }
        }
    }

    /** Makes [format] say what the AudioSpecificConfig [setup] says. */
    private fun apply(setup: ByteArray, format: MediaFormat) {
        if (setup.size < 2) return
        val a = setup[0].toInt() and 0xFF
        val b = setup[1].toInt() and 0xFF
        val objectType = a shr 3
        val rateIndex = ((a and 0x07) shl 1) or (b shr 7)
        val channels = (b shr 3) and 0x0F
        if (objectType !in 1..4 || rateIndex >= RATES.size || channels !in 1..7) return
        format.setByteBuffer("csd-0", ByteBuffer.wrap(setup.copyOf()))
        format.setInteger(MediaFormat.KEY_SAMPLE_RATE, RATES[rateIndex])
        format.setInteger(MediaFormat.KEY_CHANNEL_COUNT, channels)
    }
}
