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

  /// Whether recordings stream to a spool here.
  static bool get streams => Platform.isAndroid;

  final AudioRecorder recorder;

  /// Where the bytes are being written.
  final String path;

  final RandomAccessFile? _file;
  StreamSubscription<Uint8List>? _frames;
  final _done = Completer<void>();
  DateTime _flushed = DateTime.now();

  /// Starts [recorder] writing into [mediaDir].
  static Future<NexVoiceSpool> start(
    AudioRecorder recorder,
    String mediaDir,
  ) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (!streams) {
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
    try {
      file.writeFromSync(frame);
      // To the disk about once a second: what a dying process can lose is
      // that second, not the memo.
      final now = DateTime.now();
      if (now.difference(_flushed) > const Duration(seconds: 1)) {
        file.flushSync();
        _flushed = now;
      }
    } catch (_) {
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
    if (file == null) return recorded;
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
