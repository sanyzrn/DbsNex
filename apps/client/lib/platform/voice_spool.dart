import 'crash_reporter.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

/// A voice recording that survives the app dying halfway through (DATA-04).
///
/// An `.m4a` is written by Android's muxer, which puts the index the file
/// cannot be played without at the very end, when recording stops. A
/// process killed mid-memo — memory pressure, a crash — left a file with no
/// index: minutes of speech on disk that nothing could play, swept away an
/// hour later without a word.
///
/// On Android the recorder streams AAC frames instead, each one carrying its
/// own header (ADTS), and they go straight to a `.recording` file beside the
/// library's media. Every frame written is a frame that plays. Keep turns
/// the file into the usual `.m4a`; a recording the app never got to finish
/// is turned into one on the next launch ([recoverInterrupted]).
///
/// Elsewhere — Windows — the recorder writes its file directly, as before:
/// nothing there reclaims a running app's process.
class NexVoiceSpool {
  NexVoiceSpool._(this.recorder, this.path, this._file);

  /// The in-progress extension. Never referenced by a note, so a file with
  /// it is always one whose recording did not reach Keep.
  static const extension = '.recording';

  static const _channel = MethodChannel('nex/os_capture');

  /// Whether recordings made by the old spool can exist here: what reads
  /// and repairs them asks this.
  static bool get streams => Platform.isAndroid;

  /// Whether a new recording streams to a spool. Off, since 1.99.93.
  ///
  /// On the owner's phone every voice note made through the stream played
  /// silent — after the setup block was dropped (1.99.91) and after every
  /// header was corrected to it (1.99.92) — while a voice clip attached on
  /// the same phone, recorded straight to an `.m4a` by the recorder's own
  /// muxer, played. Whatever that phone's decoder objects to in a stream
  /// turned into a file, a voice note now is recorded the way the clip is.
  /// The cost is DATA-04's: a process killed mid-memo loses that memo.
  /// Spools left by earlier versions are still recovered.
  static const streamNewRecordings = false;

  final AudioRecorder recorder;

  /// Where the bytes are being written.
  final String path;

  final RandomAccessFile? _file;
  StreamSubscription<Uint8List>? _frames;
  final _done = Completer<void>();
  DateTime _flushed = DateTime.now();

  /// Whether a frame of real audio has been written yet.
  bool _heard = false;

  /// What the encoder says it made, from its setup block: the truth every
  /// frame's header is corrected to. Null until it arrives, or when it
  /// cannot be read — then the headers are left as the recorder wrote them.
  AdtsConfig? _config;

  /// Starts [recorder] writing into [mediaDir].
  static Future<NexVoiceSpool> start(
    AudioRecorder recorder,
    String mediaDir,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (!streams || !streamNewRecordings) {
      final path = p.join(mediaDir, 'voice-$stamp.m4a');
      await recorder.start(const RecordConfig(), path: path);
      return NexVoiceSpool._(recorder, path, null);
    }
    final path = p.join(mediaDir, 'voice-$stamp$extension');
    final file = File(path).openSync(mode: FileMode.writeOnly);
    final spool = NexVoiceSpool._(recorder, path, file);
    final frames = await recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.aacLc),
    );
    spool._frames = frames.listen(
      spool._write,
      onDone: spool._finish,
      onError: (Object _) => spool._finish(),
      cancelOnError: true,
    );
    return spool;
  }

  void _write(Uint8List frame) {
    final file = _file!;
    if (!_heard) {
      // The first frame the recorder sends is the encoder's setup, framed
      // as audio. Written down, it opened every voice note with a frame no
      // decoder can play. Kept instead for what it says: the sample rate,
      // channels and profile the encoder really used.
      if (isSetupFrame(frame)) {
        _config ??= AdtsConfig.fromSetupFrame(frame);
        return;
      }
      _heard = true;
    }
    try {
      file.writeFromSync(_config?.correct(frame) ?? frame);
      // To the disk about once a second: what a dying process can lose is
      // that second, not the memo.
      final now = DateTime.now();
      if (now.difference(_flushed) > const Duration(seconds: 1)) {
        file.flushSync();
        _flushed = now;
      }
    } catch (error) {
      unawaited(NexCrashLog.handled('voice.spool', error));
      // A full disk ends the spool, not the recording on screen; Keep then
      // reports what was saved.
    }
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete();
  }

  /// Stops recording and answers the file to keep: an `.m4a` where it could
  /// be made one, the AAC stream itself where it could not. Null when there
  /// is nothing to keep.
  Future<String?> stop() async {
    final recorded = await recorder.stop();
    final file = _file;
    if (file == null) return _kept(recorded);
    await _done.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => _frames?.cancel(),
    );
    try {
      file.flushSync();
      file.closeSync();
    } catch (_) {}
    return finish(path);
  }

  /// A file recorded straight to `.m4a`, or null when nothing was written —
  /// a recorder that failed to start leaves an empty file, which kept as a
  /// note would be a voice note that never plays.
  static String? _kept(String? recorded) {
    if (recorded == null) return null;
    final file = File(recorded);
    if (!file.existsSync()) return null;
    if (file.lengthSync() == 0) {
      file.deleteSync();
      return null;
    }
    return recorded;
  }

  /// Stops recording and deletes what was written.
  Future<void> discard() async {
    final recorded = await recorder.stop();
    await _frames?.cancel();
    try {
      _file?.closeSync();
    } catch (_) {}
    for (final candidate in [path, ?recorded]) {
      final file = File(candidate);
      if (file.existsSync()) file.deleteSync();
    }
  }

  /// Turns the spool at [spool] into the file a note keeps, and answers it.
  ///
  /// An `.m4a` beside it when the platform can repackage the stream; the
  /// stream renamed to `.aac` when it cannot, which Android still plays.
  /// Null when there is no audio in it at all.
  static Future<String?> finish(String spool) async {
    final source = File(spool);
    if (!source.existsSync() || source.lengthSync() == 0) {
      if (source.existsSync()) source.deleteSync();
      return null;
    }
    final base = spool.substring(0, spool.length - extension.length);
    final m4a = '$base.m4a';
    try {
      final made = await _channel.invokeMethod<bool>('remuxVoice', {
        'from': spool,
        'to': m4a,
      });
      if (made == true && File(m4a).existsSync()) {
        source.deleteSync();
        return m4a;
      }
    } on MissingPluginException {
      // No native half: keep the stream itself.
    } on PlatformException {
      // Same.
    }
    final aac = '$base.aac';
    source.renameSync(aac);
    return aac;
  }

  /// The file a voice note at [path] plays from: itself, or on Android a
  /// corrected copy of one recorded before 1.99.92 (`NexVoiceRemux.playable`)
  /// — those open with the encoder's setup block, and on some phones played
  /// nothing at all. The stored file is never changed.
  static Future<String> playable(String path) async {
    if (!streams) return path;
    try {
      return await _channel.invokeMethod<String>('playableVoice', {
            'path': path,
          }) ??
          path;
    } on MissingPluginException {
      return path;
    } on PlatformException {
      return path;
    }
  }

  /// Whether [frame] is an ADTS frame carrying no audio — two bytes or
  /// fewer after its header, which is the encoder's setup block.
  static bool isSetupFrame(Uint8List frame) {
    if (frame.length < 7) return false;
    if (frame[0] != 0xFF || (frame[1] & 0xF0) != 0xF0) return false;
    // No CRC when the protection-absent bit is set: a 7-byte header, else 9.
    final header = (frame[1] & 0x01) == 1 ? 7 : 9;
    final length =
        ((frame[3] & 0x03) << 11) | (frame[4] << 3) | (frame[5] >> 5);
    return length - header <= 2;
  }

  /// How long the ADTS stream in [bytes] plays, from its frame headers.
  ///
  /// Each frame says its own length and sampling rate and holds 1,024
  /// samples, so counting them is the duration — no decoder, and correct
  /// for a stream cut off mid-frame (the partial frame is not counted).
  static int adtsDurationMs(Uint8List bytes) {
    const rates = [
      96000, 88200, 64000, 48000, 44100, 32000, 24000, //
      22050, 16000, 12000, 11025, 8000, 7350,
    ];
    var offset = 0;
    var micros = 0;
    while (offset + 7 <= bytes.length) {
      if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xF0) != 0xF0) break;
      final rateIndex = (bytes[offset + 2] >> 2) & 0x0F;
      final length =
          ((bytes[offset + 3] & 0x03) << 11) |
          (bytes[offset + 4] << 3) |
          (bytes[offset + 5] >> 5);
      if (rateIndex >= rates.length || length < 7) break;
      if (offset + length > bytes.length) break;
      micros += 1024 * 1000000 ~/ rates[rateIndex];
      offset += length;
    }
    return micros ~/ 1000;
  }
}

/// The three facts an ADTS header carries about the audio — profile,
/// sampling rate and channels — as the encoder reported them.
///
/// The recorder writes each frame's header from what was asked of the
/// encoder, not from what the encoder did. On most phones the two agree. On
/// some they do not, and a voice note whose every header names the wrong
/// rate or channel count decodes to nothing: on the owner's phone, recorded
/// fine and played silent, while a clip attached on the same phone — whose
/// container takes the encoder's own account — played. The encoder's account
/// arrives first, as a two-byte AudioSpecificConfig in a frame of its own.
class AdtsConfig {
  const AdtsConfig({
    required this.objectType,
    required this.rateIndex,
    required this.channels,
  });

  /// 1 to 4: AAC Main, LC, SSR, LTP — what ADTS can say.
  final int objectType;
  final int rateIndex;
  final int channels;

  /// Reads the AudioSpecificConfig in [frame], the encoder's setup block.
  /// Null when it is not one, or says something ADTS cannot carry.
  static AdtsConfig? fromSetupFrame(Uint8List frame) {
    if (!NexVoiceSpool.isSetupFrame(frame)) return null;
    final header = (frame[1] & 0x01) == 1 ? 7 : 9;
    if (frame.length < header + 2) return null;
    final a = frame[header];
    final b = frame[header + 1];
    final objectType = a >> 3;
    final rateIndex = ((a & 0x07) << 1) | (b >> 7);
    final channels = (b >> 3) & 0x0F;
    if (objectType < 1 || objectType > 4) return null;
    if (rateIndex > 12 || channels < 1 || channels > 7) return null;
    return AdtsConfig(
      objectType: objectType,
      rateIndex: rateIndex,
      channels: channels,
    );
  }

  /// [frame] with its header saying what the encoder said. Anything that is
  /// not an ADTS frame comes back as it was.
  Uint8List correct(Uint8List frame) {
    if (frame.length < 7) return frame;
    if (frame[0] != 0xFF || (frame[1] & 0xF0) != 0xF0) return frame;
    final out = Uint8List.fromList(frame);
    // Byte 2: profile (2 bits), rate index (4), private bit (1), the top bit
    // of the channel configuration (1).
    out[2] =
        ((objectType - 1) << 6) |
        (rateIndex << 2) |
        (frame[2] & 0x02) |
        ((channels >> 2) & 0x01);
    // Byte 3: the low two bits of the channel configuration, the rest kept.
    out[3] = ((channels & 0x03) << 6) | (frame[3] & 0x3F);
    return out;
  }
}
