import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../platform/voice_spool.dart';
import 'audio_waveform.dart';
import 'steady_position.dart';

/// A recording played from its card, without opening the note (2.8.2).
///
/// One at a time, for the whole app: a second card's Play stops the first,
/// the way a single speaker would. It stops of its own accord when the note
/// is opened (its sheet has its own player), when a page is pushed over the
/// timeline, and when the app goes behind another — a card is somewhere a
/// recording is heard while looking at the list, not a background player.
class NexCardAudio extends ChangeNotifier with WidgetsBindingObserver {
  NexCardAudio._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final instance = NexCardAudio._();

  AudioPlayer? _player;
  NexSteadyPosition? _steady;
  StreamSubscription<PlayerState>? _state;
  String? _noteId;
  bool _loading = false;

  /// The note whose recording is loaded, playing or paused; null when none.
  String? get noteId => _noteId;

  /// Whether [noteId] is the one being opened right now.
  bool get loading => _loading;

  AudioPlayer? get player => _player;
  NexSteadyPosition? get steady => _steady;

  bool isPlaying(String id) =>
      _noteId == id && (_player?.playing ?? false) && !_finished;

  bool get _finished => _player?.processingState == ProcessingState.completed;

  /// Plays [note]'s recording, or pauses it when it is the one playing.
  Future<void> toggle(Note note) async {
    final uri = note.mediaUri;
    if (uri == null) return;
    if (_noteId == note.id && _player != null) {
      if (isPlaying(note.id)) {
        await _player!.pause();
      } else {
        await _steady!.play();
      }
      notifyListeners();
      return;
    }
    await stop();
    if (!File(uri).existsSync()) return;
    _noteId = note.id;
    _loading = true;
    notifyListeners();
    final player = AudioPlayer();
    try {
      // A voice note recorded before 1.99.92 plays from a corrected copy,
      // as it does in the note's own sheet.
      await player.setFilePath(
        note.type == NoteType.voice ? await NexVoiceSpool.playable(uri) : uri,
      );
      if (_noteId != note.id) {
        // Another card asked while this one was opening.
        await player.dispose();
        return;
      }
      final steady = NexSteadyPosition(player);
      _player = player;
      _steady = steady;
      _state = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed &&
            state.playing) {
          // At the end: back to the start, with Play on the button.
          unawaited(steady.rewind());
        }
        notifyListeners();
      });
      _loading = false;
      notifyListeners();
      await steady.play();
    } catch (_) {
      await player.dispose();
      if (_noteId == note.id) {
        _noteId = null;
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Moves [note]'s recording to [fraction] of its length — starting it
  /// first when it is not the one loaded.
  Future<void> seek(Note note, double fraction) async {
    if (_noteId != note.id) await toggle(note);
    final player = _player;
    final total = player?.duration;
    if (player == null || total == null || _noteId != note.id) return;
    await _steady!.seek(total * fraction);
  }

  /// Stops and lets go of whatever is playing.
  Future<void> stop() async {
    final player = _player;
    final hadOne = _noteId != null;
    _player = null;
    _steady = null;
    _noteId = null;
    _loading = false;
    await _state?.cancel();
    _state = null;
    if (hadOne) notifyListeners();
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
      await player.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }
}

/// The one [NexCardAudioObserver] the app's navigator carries.
final nexCardAudioObserver = NexCardAudioObserver();

/// Stops a card's recording when a page is pushed over the screen it plays
/// on. A sheet over the list — a menu, the tag picker — leaves it playing.
class NexCardAudioObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) unawaited(NexCardAudio.instance.stop());
  }
}

/// "1:05" — a length, when the card's strings have none of their own.
String nexDefaultDurationLabel(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A recording on a card: Play, the recording's shape, and its time.
///
/// The shape is the note's own, read from the file and drawn in its kind's
/// colour; a touch or a drag along it moves playback there. Time counts down
/// what is left while it plays, and shows the whole length while it does not.
class NexCardVoice extends StatelessWidget {
  const NexCardVoice({
    super.key,
    required this.note,
    required this.tint,
    required this.durationLabel,
    this.compact = false,
    this.height,
    this.playLabel = 'Play',
    this.pauseLabel = 'Pause',
  });

  final Note note;
  final Color tint;
  final String Function(int milliseconds) durationLabel;

  /// A list card's single line, rather than a tile's taller strip.
  final bool compact;

  /// The room the strip has, when it is less than a finger's width: the
  /// disc and its touch shrink to it rather than spill out of a card.
  final double? height;
  final String playLabel;
  final String pauseLabel;

  @override
  Widget build(BuildContext context) {
    final uri = note.mediaUri;
    if (uri == null) return const SizedBox.shrink();
    final audio = NexCardAudio.instance;
    final room = height ?? 44.0;
    final size = math.min(compact ? 32.0 : 36.0, room - 4);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final mine = audio.noteId == note.id;
        final playing = audio.isPlaying(note.id);
        final player = mine ? audio.player : null;
        return Row(
          children: [
            _PlayDisc(
              key: ValueKey('card-play-${note.id}'),
              size: size,
              target: math.min(44, room),
              tint: tint,
              playing: playing,
              loading: mine && audio.loading,
              label: playing ? pauseLabel : playLabel,
              onTap: () {
                nexTick();
                unawaited(audio.toggle(note));
              },
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: player?.positionStream,
                builder: (context, position) {
                  final total =
                      player?.duration ??
                      Duration(milliseconds: note.durationMs ?? 0);
                  final at = mine && audio.steady != null
                      ? audio.steady!.of(position.data ?? Duration.zero)
                      : Duration.zero;
                  final progress = total.inMilliseconds <= 0
                      ? 0.0
                      : (at.inMilliseconds / total.inMilliseconds).clamp(
                          0.0,
                          1.0,
                        );
                  final left = mine && at > Duration.zero ? total - at : total;
                  return Row(
                    children: [
                      Expanded(
                        child: AudioWaveform(
                          path: uri,
                          progress: progress,
                          height: math.min(
                            compact ? 22 : room * 0.66,
                            room - 6,
                          ),
                          played: tint,
                          onSeek: (fraction) =>
                              unawaited(audio.seek(note, fraction)),
                        ),
                      ),
                      if (left.inMilliseconds > 0) ...[
                        const SizedBox(width: NexSpacing.xs + 2),
                        Text(
                          durationLabel(left.inMilliseconds),
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                fontWeight: mine ? FontWeight.w700 : null,
                              ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Play or pause, a disc in the note's colour, the glyph turning between the
/// two.
class _PlayDisc extends StatelessWidget {
  const _PlayDisc({
    super.key,
    required this.size,
    required this.target,
    required this.tint,
    required this.playing,
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final double size;
  final double target;
  final Color tint;
  final bool playing;
  final bool loading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = nexReadableOn(Colors.white, tint);
    // The touch reaches a finger's width round the disc.
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox.square(
          dimension: target,
          child: Center(
            child: AnimatedContainer(
              duration: NexMotion.of(context, NexMotion.fast),
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tint,
                boxShadow: playing
                    ? [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.35),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
              child: loading
                  ? Padding(
                      padding: EdgeInsets.all(size * 0.28),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ink,
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: NexMotion.of(context, NexMotion.fast),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey(playing),
                        size: size * 0.58,
                        color: ink,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A recording's list card, playable where it is (2.8.2): the player in the
/// card's preview rows, and the note's first words above it when the card
/// size leaves a row for them (the larger size).
class NexCardVoicePreview extends StatelessWidget {
  const NexCardVoicePreview({
    super.key,
    required this.note,
    required this.strings,
  });

  final Note note;
  final NexCardStrings strings;

  /// Whether [note]'s card plays its recording at this [density].
  static bool fits(Note note, NexCardDensity density) =>
      note.isAudioMedia && note.mediaUri != null && density.lines >= 2;

  @override
  Widget build(BuildContext context) {
    final row = nexCardPreviewLineHeightFor(context);
    final lines = NexCardDensity.of(context).lines;
    final words = (note.displayText ?? '').trim();
    final withWords = lines >= 3 && words.isNotEmpty;
    final strip = row * (withWords ? lines - 1 : lines);
    final scheme = Theme.of(context).colorScheme;
    final tint = nexNoteWash(note.type.wireName, scheme).tint;
    return Column(
      key: const ValueKey('card-voice'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (withWords)
          SizedBox(
            height: row,
            child: NexTextSurface(
              NexMarkdownText.preview(words),
              maxLines: 1,
              style: NexCardDensity.of(context).previewStyle(Theme.of(context)),
            ),
          ),
        SizedBox(
          height: strip,
          child: NexCardVoice(
            note: note,
            tint: tint,
            compact: true,
            height: strip,
            durationLabel: strings.durationLabel ?? nexDefaultDurationLabel,
            playLabel: strings.playLabel ?? 'Play',
            pauseLabel: strings.pauseLabel ?? 'Pause',
          ),
        ),
      ],
    );
  }
}
