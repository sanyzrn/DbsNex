import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'pause_patterns.dart';
import 'pause_synth.dart';

/// What a breathing session asks of sound.
///
/// Every call is best-effort: a phone with no audio, a player that fails to
/// load, a test with no platform — the session goes on in silence, because
/// the guide is the motion and the haptics as much as the sound.
abstract class PauseSound {
  /// Makes the session's sounds ready. Safe to call before the countdown and
  /// not wait for: the first sound is a second away.
  Future<void> prepare(PauseMode mode);

  Future<void> countdown();

  /// The round's sound, looping from its start.
  Future<void> startBreathing();

  /// Stops the breathing and rings the bowl.
  Future<void> finish();

  /// Pausing the session pauses the sound where it is; resuming carries on.
  Future<void> pause();
  Future<void> resume();

  void setMuted(bool muted);

  Future<void> dispose();
}

/// Makes the [PauseSound] a session uses. A test swaps in a silent one,
/// since a test has no audio platform to play through.
PauseSound Function() pauseSoundFactory = NexPauseSound.new;

class SilentPauseSound implements PauseSound {
  @override
  Future<void> prepare(PauseMode mode) async {}
  @override
  Future<void> countdown() async {}
  @override
  Future<void> startBreathing() async {}
  @override
  Future<void> finish() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  void setMuted(bool muted) {}
  @override
  Future<void> dispose() async {}
}

/// Two players: one loops the breath, one plays the taps and the bowl over
/// it. The sounds are made once, off the UI thread, and kept as WAV files in
/// the app's cache, so a second session starts without making them again.
class NexPauseSound implements PauseSound {
  AudioPlayer? _breath;
  AudioPlayer? _cue;
  Future<_Files?>? _files;
  bool _muted = false;

  /// Bumped when the sounds change, so an old file is not played for a new
  /// design.
  static const _version = 1;

  @override
  Future<void> prepare(PauseMode mode) {
    final files = _files ??= _make(mode);
    return files.then((files) async {
      if (files == null) return;
      await _safely(() async {
        final breath = _breath ??= AudioPlayer();
        final cue = _cue ??= AudioPlayer();
        await breath.setFilePath(files.round);
        await breath.setLoopMode(LoopMode.one);
        await cue.setFilePath(files.countdown);
        _apply();
      });
    });
  }

  @override
  Future<void> countdown() => _safely(() async {
    final cue = _cue;
    if (cue == null) return;
    await cue.seek(Duration.zero);
    unawaited(cue.play());
  });

  @override
  Future<void> startBreathing() => _safely(() async {
    final breath = _breath;
    if (breath == null) return;
    await breath.seek(Duration.zero);
    unawaited(breath.play());
  });

  @override
  Future<void> finish() => _safely(() async {
    await _breath?.stop();
    final files = await _files;
    final cue = _cue;
    if (files == null || cue == null) return;
    await cue.setFilePath(files.bowl);
    unawaited(cue.play());
  });

  @override
  Future<void> pause() => _safely(() async {
    await _breath?.pause();
    await _cue?.pause();
  });

  @override
  Future<void> resume() => _safely(() async {
    final breath = _breath;
    if (breath != null && breath.processingState != ProcessingState.idle) {
      unawaited(breath.play());
    }
  });

  @override
  void setMuted(bool muted) {
    _muted = muted;
    _apply();
  }

  void _apply() {
    unawaited(
      _safely(() => _breath?.setVolume(_muted ? 0 : 1) ?? Future.value()),
    );
    unawaited(_safely(() => _cue?.setVolume(_muted ? 0 : 1) ?? Future.value()));
  }

  @override
  Future<void> dispose() async {
    final breath = _breath;
    final cue = _cue;
    _breath = null;
    _cue = null;
    await _safely(() async => breath?.dispose());
    await _safely(() async => cue?.dispose());
  }

  static Future<_Files?> _make(PauseMode mode) async {
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'nex_pause'),
      );
      final round = p.join(dir.path, '${mode.id}_v$_version.wav');
      final countdown = p.join(dir.path, 'countdown_v$_version.wav');
      final bowl = p.join(dir.path, 'bowl_v$_version.wav');
      await Isolate.run(() {
        dir.createSync(recursive: true);
        void write(String path, Float32List Function() make) {
          final file = File(path);
          if (!file.existsSync()) file.writeAsBytesSync(pauseWav(make()));
        }

        write(round, () => pauseSynthRound(mode));
        write(countdown, pauseSynthCountdown);
        write(bowl, pauseSynthBowl);
      });
      return _Files(round: round, countdown: countdown, bowl: bowl);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Sound is a nicety; the session carries on without it.
    }
  }
}

class _Files {
  const _Files({
    required this.round,
    required this.countdown,
    required this.bowl,
  });

  final String round;
  final String countdown;
  final String bowl;
}
