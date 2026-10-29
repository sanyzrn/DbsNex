import 'dart:math' as math;

/// What the breath is doing.
enum PauseStep { inhale, holdFull, exhale, holdEmpty }

/// One part of a breath and how long it lasts.
class PausePhase {
  const PausePhase(this.step, this.millis);

  final PauseStep step;
  final int millis;

  Duration get duration => Duration(milliseconds: millis);
}

/// The three breathing breaks.
///
/// Nothing publishes the timings behind its own Breathing break, so these
/// are the patterns the three names usually stand for:
///
///  * Calm — balanced breathing, five and a half seconds in and five and a
///    half out: about five breaths a minute, the pace studies of slow
///    breathing settle on for a steady heart rate.
///  * Focus — box breathing, four in, four held, four out, four held: even,
///    countable, the pattern taught for staying clear under pressure.
///  * Relax — 4-7-8: in for four, held for seven, out for eight. The long
///    exhale is the part that winds down; four rounds is the usual limit for
///    someone new to it.
///
/// Every round ends empty, so a session can loop a round's sound without a
/// seam and stop at the end of any one of them.
enum PauseMode {
  calm('calm', [
    PausePhase(PauseStep.inhale, 5500),
    PausePhase(PauseStep.exhale, 5500),
  ], 10),
  focus('focus', [
    PausePhase(PauseStep.inhale, 4000),
    PausePhase(PauseStep.holdFull, 4000),
    PausePhase(PauseStep.exhale, 4000),
    PausePhase(PauseStep.holdEmpty, 4000),
  ], 6),
  relax('relax', [
    PausePhase(PauseStep.inhale, 4000),
    PausePhase(PauseStep.holdFull, 7000),
    PausePhase(PauseStep.exhale, 8000),
  ], 4);

  const PauseMode(this.id, this.phases, this.rounds);

  /// Stored in preferences.
  final String id;
  final List<PausePhase> phases;

  /// Breaths in one session.
  final int rounds;

  static PauseMode fromId(String id) =>
      values.firstWhere((m) => m.id == id, orElse: () => calm);

  int get roundMillis => phases.fold(0, (sum, p) => sum + p.millis);

  Duration get roundDuration => Duration(milliseconds: roundMillis);

  Duration get sessionDuration => roundDuration * rounds;

  /// "5.5 · 5.5", "4 · 4 · 4 · 4", "4 · 7 · 8": the seconds of each part.
  String get rhythm => [
    for (final p in phases)
      p.millis % 1000 == 0
          ? '${p.millis ~/ 1000}'
          : (p.millis / 1000).toStringAsFixed(1),
  ].join(' · ');
}

/// Where a session is at a moment in its breathing.
class PauseMoment {
  const PauseMoment({
    required this.round,
    required this.phase,
    required this.progress,
    required this.fullness,
    required this.done,
  });

  /// Zero-based.
  final int round;
  final PausePhase phase;

  /// 0–1 through [phase].
  final double progress;

  /// How full the lungs are, 0–1, eased the way a breath is: slow at the
  /// turns, quickest in the middle.
  final double fullness;

  /// Past the last round.
  final bool done;

  /// Seconds left in the current part, counting down to 1.
  int get secondsLeft =>
      math.max(1, ((1 - progress) * phase.millis / 1000).ceil());
}

/// A breath's ease: sine in and out, so the motion never jerks at a turn.
double pauseEase(double t) => 0.5 - math.cos(math.pi * t.clamp(0.0, 1.0)) / 2;

/// The moment [elapsed] into the breathing of a [mode] session.
PauseMoment pauseMomentAt(PauseMode mode, Duration elapsed) {
  final total = mode.roundMillis * mode.rounds;
  final at = elapsed.inMilliseconds.clamp(0, total);
  if (at >= total) {
    return PauseMoment(
      round: mode.rounds - 1,
      phase: mode.phases.last,
      progress: 1,
      fullness: 0,
      done: true,
    );
  }
  final round = at ~/ mode.roundMillis;
  var into = at % mode.roundMillis;
  for (final phase in mode.phases) {
    if (into < phase.millis) {
      final p = into / phase.millis;
      return PauseMoment(
        round: round,
        phase: phase,
        progress: p,
        fullness: switch (phase.step) {
          PauseStep.inhale => pauseEase(p),
          PauseStep.holdFull => 1,
          PauseStep.exhale => 1 - pauseEase(p),
          PauseStep.holdEmpty => 0,
        },
        done: false,
      );
    }
    into -= phase.millis;
  }
  // Unreachable: [into] is less than the round's length.
  return PauseMoment(
    round: round,
    phase: mode.phases.last,
    progress: 1,
    fullness: 0,
    done: false,
  );
}

/// The points in a part of the breath where the phone taps, as fractions of
/// it: closer and closer together as an inhale fills, further and further
/// apart as an exhale empties, and one at the start of a hold. Felt with the
/// eyes closed, the spacing is the breath.
List<double> pauseTapsFor(PauseStep step) => switch (step) {
  PauseStep.inhale => const [0, 0.3, 0.52, 0.68, 0.8, 0.89, 0.95],
  PauseStep.exhale => const [0, 0.05, 0.11, 0.2, 0.32, 0.48, 0.7],
  PauseStep.holdFull || PauseStep.holdEmpty => const [0],
};
