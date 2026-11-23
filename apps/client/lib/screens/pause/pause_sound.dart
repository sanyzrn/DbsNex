import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_session/audio_session.dart';
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

  /// Fires once each time the platform takes the sound away mid-session — a
  /// call, another player, headphones unplugged — so the session can hold its
  /// breath with it instead of carrying on in silence (2.8.14).
  Stream<void> get interruptions;

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
  Stream<void> get interruptions => const Stream.empty();
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
  _Files? _files;
  Future<void>? _preparation;
  Future<void> _commands = Future.value();
  StreamSubscription<AudioInterruptionEvent>? _focusEvents;
  StreamSubscription<void>? _noisyEvents;
  final _interruptions = StreamController<void>.broadcast();
  bool _muted = false;
  bool _disposed = false;
  bool _guiding = false;
  bool _cueIsCountdown = true;
  int _request = 0;

  @override
  Stream<void> get interruptions => _interruptions.stream;

  /// Bump when the cached WAV design changes.
  static const _version = 1;

  @override
  Future<void> prepare(PauseMode mode) =>
      _preparation ??= _safely(() => _prepare(mode)).whenComplete(() {
        // A preparation that never reached its files is not kept (2.8.19):
        // cached, it left every later session silent and «Again» could not
        // bring the sound back. The half-made players go with it.
        if (_files != null || _disposed) return;
        _preparation = null;
        final breath = _breath, cue = _cue;
        _breath = null;
        _cue = null;
        unawaited(_safely(() async => breath?.dispose()));
        unawaited(_safely(() async => cue?.dispose()));
      });

  Future<void> _prepare(PauseMode mode) async {
    final files = await _make(mode);
    if (_disposed || files == null) return;
    // Pause owns focus events so returning focus cannot restart sound while
    // the visual guide is still waiting for the user to resume.
    final breath = _breath = AudioPlayer(handleInterruptions: false);
    final cue = _cue = AudioPlayer(handleInterruptions: false);
    await breath.setFilePath(files.round);
    await breath.setLoopMode(LoopMode.one);
    await cue.setFilePath(files.countdown);
    await _safely(_listenForInterruptions);
    if (_disposed) return;
    _applyVolume();
    _files = files;
  }

  Future<void> _listenForInterruptions() async {
    final session = await AudioSession.instance;
    if (_disposed) return;
    _focusEvents = session.interruptionEventStream.listen((event) {
      if (event.begin && event.type != AudioInterruptionType.duck) {
        _soundTaken();
      }
    });
    _noisyEvents = session.becomingNoisyEventStream.listen(
      (_) => _soundTaken(),
    );
  }

  void _soundTaken() {
    if (_muted || _disposed) return;
    final guiding = _guiding;
    if (!guiding && _cue?.playing != true) return;
    unawaited(pause());
    if (guiding) _interruptions.add(null);
  }

  /// A pause may be followed by resume while the platform is still handling
  /// it. Keep player commands in order and suppress superseded starts.
  Future<void> _enqueue(Future<void> Function() command) => _commands =
      _commands.then((_) => _disposed ? Future.value() : _safely(command));

  bool _current(int request) => !_disposed && request == _request;

  void _play(AudioPlayer player) => unawaited(_safely(player.play));

  @override
  Future<void> countdown() {
    final request = ++_request;
    return _enqueue(() async {
      final files = _files;
      final cue = _cue;
      if (!_current(request) || files == null || cue == null) return;
      if (_cueIsCountdown) {
        await cue.seek(Duration.zero);
      } else {
        await cue.setFilePath(files.countdown);
        _cueIsCountdown = true;
      }
      if (!_current(request)) return;
      _guiding = true;
      _play(cue);
    });
  }

  @override
  Future<void> startBreathing() => _playBreath(fromStart: true);

  @override
  Future<void> resume() => _playBreath(fromStart: false);

  Future<void> _playBreath({required bool fromStart}) {
    final request = ++_request;
    return _enqueue(() async {
      final breath = _breath;
      if (!_current(request) || _files == null || breath == null) return;
      if (fromStart) await breath.seek(Duration.zero);
      if (!_current(request)) return;
      _guiding = true;
      _play(breath);
    });
  }

  @override
  Future<void> finish() {
    final request = ++_request;
    _guiding = false;
    return _enqueue(() async {
      if (!_current(request)) return;
      await _breath?.stop();
      final files = _files;
      final cue = _cue;
      if (!_current(request) || files == null || cue == null) return;
      await cue.setFilePath(files.bowl);
      _cueIsCountdown = false;
      if (_current(request)) _play(cue);
    });
  }

  @override
  Future<void> pause() {
    _request++;
    _guiding = false;
    return _enqueue(() async {
      await Future.wait([
        if (_breath case final breath?) breath.pause(),
        if (_cue case final cue?) cue.pause(),
      ]);
    });
  }

  @override
  void setMuted(bool muted) {
    _muted = muted;
    _applyVolume();
  }

  void _applyVolume() {
    final volume = _muted ? 0.0 : 1.0;
    if (_breath case final breath?) {
      unawaited(_safely(() => breath.setVolume(volume)));
    }
    if (_cue case final cue?) {
      unawaited(_safely(() => cue.setVolume(volume)));
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final breath = _breath;
    final cue = _cue;
    _breath = null;
    _cue = null;
    await _focusEvents?.cancel();
    await _noisyEvents?.cancel();
    unawaited(_interruptions.close());
    await Future.wait([
      if (breath != null) _safely(breath.dispose),
      if (cue != null) _safely(cue.dispose),
    ]);
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
