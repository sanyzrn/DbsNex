import 'dart:math' as math;
import 'dart:typed_data';

import 'pause_patterns.dart';

/// The sound of a breathing break, made in code rather than shipped.
///
/// Nothing here is a recording, so nothing has a licence to check and the
/// app grows by no audio files. Each sound is a few oscillators and a little
/// filtered noise, written into a WAV the player loops:
///
///  * a round — one whole breath, looped for the session. A soft chord swells
///    and brightens as the lungs fill and settles as they empty, a band of
///    air rises with the inhale and falls with the exhale, and a small chime
///    marks each in-breath and a lower one each out-breath, so the guide can
///    be followed with the eyes closed;
///  * the countdown — three soft wooden taps, one a second;
///  * the bowl — a singing bowl struck once, for the end.
///
/// Each mode has its own chord: Calm an open D major ninth, Focus bare
/// fifths on A, Relax a low F major seventh.
const pauseSampleRate = 22050;

/// One round of [mode]'s breathing, ready to loop.
Float32List pauseSynthRound(PauseMode mode) {
  final rate = pauseSampleRate;
  final length = mode.roundMillis * rate ~/ 1000;
  final out = Float32List(length);
  final chord = _chords[mode]!;
  final random = math.Random(7 + mode.index);

  // Oscillator phases, carried across the whole round so nothing clicks at a
  // phase boundary. Each note is a pair a fraction of a hertz apart, which
  // makes the slow shimmer of a held chord.
  final phases = List<double>.filled(chord.length * 2 + 1, 0);
  var low = 0.0;
  var lower = 0.0;
  var lowest = 0.0;

  for (var i = 0; i < length; i++) {
    final t = i / rate;
    final moment = pauseMomentAt(
      mode,
      Duration(microseconds: (t * 1000000).round()),
    );
    final f = moment.fullness;
    final step = moment.phase.step;

    // The chord: louder and a hair sharper with a full breath.
    final bend = 1 + 0.008 * f;
    final tremolo = 1 + 0.08 * math.sin(2 * math.pi * 0.23 * t);
    var pad = 0.0;
    for (var n = 0; n < chord.length; n++) {
      final (hz, level) = chord[n];
      // Each note beats at its own slow rate, and the second voice is
      // quieter, so the chord shimmers rather than pulsing as one.
      final drift = _drift[n];
      for (var d = 0; d < 2; d++) {
        final k = n * 2 + d;
        phases[k] +=
            2 * math.pi * (hz + (d == 0 ? -drift : drift)) * bend / rate;
        pad += math.sin(phases[k]) * level * (d == 0 ? 1 : 0.55);
      }
    }
    // An octave over the top note, only near a full breath: the brightening.
    final top = chord.last.$1 * 2;
    phases[chord.length * 2] += 2 * math.pi * top * bend / rate;
    pad += math.sin(phases[chord.length * 2]) * 0.18 * f * f;
    pad *= (0.22 + 0.78 * f) * tremolo * 0.16;

    // The air: white noise through two one-pole filters, one minus the other
    // — a band whose centre rises on the inhale and falls on the exhale, and
    // whose loudness follows how fast the breath is moving.
    final air = switch (step) {
      PauseStep.inhale ||
      PauseStep.exhale => math.sin(math.pi * moment.progress),
      _ => 0.0,
    };
    final cutoff = switch (step) {
      PauseStep.inhale => 450 + 1400 * moment.progress,
      PauseStep.exhale => 1500 - 1150 * moment.progress,
      _ => 600.0,
    };
    final a = 1 - math.exp(-2 * math.pi * cutoff / rate);
    final b = 1 - math.exp(-2 * math.pi * cutoff / 5 / rate);
    final white = random.nextDouble() * 2 - 1;
    low += a * (white - low);
    lower += a * (low - lower);
    lowest += b * (lower - lowest);
    final breath = (lower - lowest) * air * air * 0.5;

    out[i] = pad + breath;
  }

  // The cues, laid over the start of each in- and out-breath.
  var at = 0;
  for (final phase in mode.phases) {
    final start = at * rate ~/ 1000;
    switch (phase.step) {
      case PauseStep.inhale:
        _addChime(out, start, chord.last.$1 * 2, 0.07);
      case PauseStep.exhale:
        _addChime(out, start, chord.last.$1 * 1.5, 0.05);
      case PauseStep.holdFull || PauseStep.holdEmpty:
        break;
    }
    at += phase.millis;
  }

  _fadeEdges(out, rate ~/ 40);
  _normalize(out, 0.7);
  return out;
}

/// Three soft wooden taps, a second apart.
Float32List pauseSynthCountdown() {
  final rate = pauseSampleRate;
  final out = Float32List(rate * 3);
  for (var n = 0; n < 3; n++) {
    final start = n * rate;
    final length = rate ~/ 6;
    var phase = 0.0;
    for (var i = 0; i < length && start + i < out.length; i++) {
      final t = i / rate;
      // A quick downward glide is what makes it wood rather than a beep.
      final hz = 700 + 500 * math.exp(-t * 60);
      phase += 2 * math.pi * hz / rate;
      out[start + i] += math.sin(phase) * math.exp(-t * 38) * 0.6;
    }
  }
  _normalize(out, 0.45);
  return out;
}

/// A singing bowl struck once and left to ring.
///
/// A bowl's partials are not harmonics — they sit at about 2.7, 5.2 and 8.2
/// times the fundamental — and each pair of them beats slowly, which is the
/// "wah" that makes a bowl sound like a bowl and not a bell.
Float32List pauseSynthBowl({double hz = 196}) {
  final rate = pauseSampleRate;
  final length = rate * 7;
  final out = Float32List(length);
  const partials = [
    (1.0, 1.0, 0.55, 0.7),
    (2.71, 0.5, 0.9, 1.1),
    (5.18, 0.22, 1.6, 1.6),
    (8.19, 0.1, 2.6, 2.1),
  ];
  final random = math.Random(3);
  for (var i = 0; i < length; i++) {
    final t = i / rate;
    var s = 0.0;
    for (final (ratio, level, decay, beat) in partials) {
      final f = hz * ratio;
      s +=
          (math.sin(2 * math.pi * f * t) +
              math.sin(2 * math.pi * (f + beat) * t)) *
          level *
          math.exp(-t * decay);
    }
    // The strike: a few milliseconds of soft noise.
    final strike = t < 0.012 ? (random.nextDouble() * 2 - 1) * 0.3 : 0.0;
    final attack = math.min(1.0, t / 0.004);
    out[i] = (s * 0.5 + strike) * attack;
  }
  _fadeEdges(out, rate ~/ 10, start: false);
  _normalize(out, 0.6);
  return out;
}

/// Mono 16-bit PCM, the plainest WAV there is — every player reads it.
Uint8List pauseWav(Float32List samples, {int rate = pauseSampleRate}) {
  final data = samples.length * 2;
  final bytes = ByteData(44 + data);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + data, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, v, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Half the beat rate of each note's two voices, in hertz.
const _drift = [0.11, 0.17, 0.23, 0.29];

/// Hertz and level for each note of a mode's chord, lowest first.
const _chords = {
  PauseMode.calm: [(146.83, 1.0), (220.0, 0.8), (369.99, 0.55), (659.26, 0.3)],
  PauseMode.focus: [(110.0, 1.0), (164.81, 0.8), (329.63, 0.5), (493.88, 0.3)],
  PauseMode.relax: [(87.31, 1.0), (130.81, 0.8), (220.0, 0.5), (329.63, 0.28)],
};

/// A small glass chime: a sine and its fifth, gone in two seconds.
void _addChime(Float32List out, int start, double hz, double level) {
  final rate = pauseSampleRate;
  final length = math.min(rate * 2, out.length - start);
  for (var i = 0; i < length; i++) {
    final t = i / rate;
    final env = math.min(1.0, t / 0.006) * math.exp(-t * 2.4);
    out[start + i] +=
        (math.sin(2 * math.pi * hz * t) +
            0.4 * math.sin(2 * math.pi * hz * 1.5 * t)) *
        env *
        level;
  }
}

void _fadeEdges(Float32List out, int length, {bool start = true}) {
  final n = math.min(length, out.length ~/ 2);
  for (var i = 0; i < n; i++) {
    final g = i / n;
    if (start) out[i] *= g;
    out[out.length - 1 - i] *= g;
  }
}

void _normalize(Float32List out, double peak) {
  var max = 0.0;
  for (final s in out) {
    max = math.max(max, s.abs());
  }
  if (max == 0) return;
  final g = peak / max;
  for (var i = 0; i < out.length; i++) {
    out[i] *= g;
  }
}
