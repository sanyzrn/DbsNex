import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart' show nexDigits;
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'audio_waveform.dart';
import 'steady_position.dart';

/// A recording, played where it is: a voice note, an audio file, a voice
/// clip attached to a note.
///
/// One card in the accent's light. A round button that turns play into
/// pause and glows while it plays; the recording's own shape as the bar,
/// played part in the accent, touched or dragged to move; under it how far
/// along, how fast, and how long.
///
/// It is there the moment the note is: [steady] is null while the file is
/// still being opened, and the card shows in full — its length from [length],
/// a stand-in shape, the button waiting — so nothing appears a second later
/// and pushes the note down. It was a row that only came into being once the
/// player was ready.
class NexVoicePlayer extends StatefulWidget {
  const NexVoicePlayer({
    super.key,
    required this.path,
    required this.steady,
    this.length = Duration.zero,
  });

  /// The file, for its shape. Null draws the stand-in.
  final String? path;

  /// The player, once the file is open.
  final NexSteadyPosition? steady;

  /// How long it is, as known before the player says.
  final Duration length;

  static const _speeds = [1.0, 1.5, 2.0];

  @override
  State<NexVoicePlayer> createState() => _NexVoicePlayerState();
}

class _NexVoicePlayerState extends State<NexVoicePlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: NexMotion.standard,
  );
  int _speed = 0;

  // The file opens after the card is up, and the speed chosen while it was
  // opening — or before a sheet swapped the player — belongs to the new one.
  @override
  void didUpdateWidget(NexVoicePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final steady = widget.steady;
    if (steady != null && steady != oldWidget.steady && _speed != 0) {
      unawaited(steady.player.setSpeed(NexVoicePlayer._speeds[_speed]));
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  String _clock(Duration value, bool persian) {
    final seconds = value.inSeconds;
    return nexDigits(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      persian: persian,
    );
  }

  Future<void> _toggle(bool playing) async {
    final steady = widget.steady;
    if (steady == null) return;
    if (playing) {
      await steady.player.pause();
    } else {
      await steady.play();
    }
  }

  void _nextSpeed() {
    final steady = widget.steady;
    if (steady == null) return;
    setState(() => _speed = (_speed + 1) % NexVoicePlayer._speeds.length);
    unawaited(steady.player.setSpeed(NexVoicePlayer._speeds[_speed]));
  }

  @override
  Widget build(BuildContext context) {
    final player = widget.steady?.player;
    return StreamBuilder<PlayerState>(
      stream: player?.playerStateStream,
      builder: (context, state) {
        final playing =
            (state.data?.playing ?? false) &&
            state.data?.processingState != ProcessingState.completed;
        _morph.duration = NexMotion.of(context, NexMotion.standard);
        if (playing) {
          unawaited(_morph.forward());
        } else {
          unawaited(_morph.reverse());
        }
        return StreamBuilder<Duration?>(
          stream: player?.durationStream,
          builder: (context, length) {
            final total = (length.data ?? Duration.zero) > Duration.zero
                ? length.data!
                : widget.length;
            return StreamBuilder<Duration>(
              stream: player?.positionStream,
              builder: (context, position) {
                final steady = widget.steady;
                final at = steady == null
                    ? Duration.zero
                    : steady.of(position.data ?? Duration.zero);
                return _card(context, playing: playing, at: at, total: total);
              },
            );
          },
        );
      },
    );
  }

  Widget _card(
    BuildContext context, {
    required bool playing,
    required Duration at,
    required Duration total,
  }) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final ready = widget.steady != null;
    final whole = total.inMilliseconds;
    final fraction = whole <= 0
        ? 0.0
        : (at.inMilliseconds / whole).clamp(0.0, 1.0);
    final path = widget.path;
    final tabular = const [FontFeature.tabularFigures()];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(NexRadius.lg),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            scheme.primary.withValues(alpha: 0.12),
            scheme.primary.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Row(
          children: [
            _PlayButton(
              morph: _morph,
              playing: playing,
              ready: ready,
              tooltip: playing ? l10n.pauseAudio : l10n.playAudio,
              onPressed: () => unawaited(_toggle(playing)),
            ),
            const SizedBox(width: NexSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    slider: true,
                    label: l10n.playAudio,
                    value: _clock(at, persian),
                    child: path == null
                        ? const SizedBox(height: 40)
                        : AudioWaveform(
                            path: path,
                            progress: fraction,
                            onSeek: ready && whole > 0
                                ? (to) => unawaited(
                                    widget.steady!.seek(
                                      Duration(
                                        milliseconds: (to * whole).round(),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  // Times read left to right, as on every media bar.
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Row(
                      children: [
                        Text(
                          _clock(at, persian),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabular,
                          ),
                        ),
                        const Spacer(),
                        _SpeedChip(
                          label: nexDigits(
                            '${_speedLabel(NexVoicePlayer._speeds[_speed])}×',
                            persian: persian,
                          ),
                          onTap: ready ? _nextSpeed : null,
                        ),
                        const SizedBox(width: NexSpacing.sm),
                        Text(
                          _clock(total, persian),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? '${speed.round()}' : '$speed';
}

/// Play and pause in one shape that turns into the other, glowing softly
/// while it plays, and dimmed while the file opens — no spinner, which would
/// turn for ever on a file that never does.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.morph,
    required this.playing,
    required this.ready,
    required this.tooltip,
    required this.onPressed,
  });

  final Animation<double> morph;
  final bool playing;
  final bool ready;
  final String tooltip;
  final VoidCallback onPressed;

  static const _size = 52.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: ready,
        label: tooltip,
        child: AnimatedContainer(
          duration: NexMotion.of(context, NexMotion.standard),
          curve: NexMotion.curve,
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.primary.withValues(alpha: ready ? 1 : 0.55),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: playing ? 0.45 : 0.18),
                blurRadius: playing ? 18 : 8,
                spreadRadius: playing ? 1 : 0,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('voice-player-play'),
              onTap: ready ? onPressed : null,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ExcludeSemantics(
                    child: AnimatedIcon(
                      icon: AnimatedIcons.play_pause,
                      progress: morph,
                      size: 28,
                      color: scheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How fast: 1×, 1.5×, 2×, around again.
class _SpeedChip extends StatelessWidget {
  const _SpeedChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('voice-player-speed'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.sm,
            vertical: 2,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
