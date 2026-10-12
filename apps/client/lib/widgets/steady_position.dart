import 'package:just_audio/just_audio.dart';

/// Where a player is, for a progress bar to show, without the jump back as
/// playback starts.
///
/// just_audio reports a playing clip's position by guessing forward from its
/// last report. Between "play" and the platform actually starting, the guess
/// runs ahead; the platform's first real report then says the very start, and
/// the bar ran forward a fraction of a second only to snap back and begin
/// again. A small step back is that correction, so it is held until the real
/// position passes it. A seek is a real step back: [seek] says so.
class NexSteadyPosition {
  NexSteadyPosition(this.player);

  final AudioPlayer player;

  /// The most a guess has been seen to run ahead.
  static const _slack = Duration(milliseconds: 600);

  Duration _shown = Duration.zero;

  /// [actual], or what was shown already when [actual] is only the player
  /// taking back its own guess.
  Duration of(Duration actual) {
    if (actual < _shown && _shown - actual < _slack) return _shown;
    return _shown = actual;
  }

  /// Moves the player to [to], and the bar with it.
  Future<void> seek(Duration to) {
    _shown = to;
    return player.seek(to);
  }

  /// Play, from the start when the clip has played to its end.
  Future<void> play() async {
    if (player.processingState == ProcessingState.completed) {
      await seek(Duration.zero);
    }
    await player.play();
  }

  /// At the end of the clip: stopped, back at the start, ready to play
  /// again — rather than "playing" a clip that has nothing left.
  Future<void> rewind() async {
    await player.pause();
    await seek(Duration.zero);
  }
}
