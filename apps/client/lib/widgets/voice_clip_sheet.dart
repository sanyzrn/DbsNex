import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';
import 'steady_position.dart';

/// A voice clip attached to a note, played where it is: a sheet with one
/// large play button, how far along it is, its caption and, once it has been
/// transcribed, what was said. Closing the sheet stops it.
class VoiceClipSheet extends StatefulWidget {
  const VoiceClipSheet({super.key, required this.attachment});

  final NoteAttachment attachment;

  static Future<void> show(
    BuildContext context, {
    required NoteAttachment attachment,
  }) => nexShowSheet<void>(
    context: context,
    builder: (_) => VoiceClipSheet(attachment: attachment),
  );

  @override
  State<VoiceClipSheet> createState() => _VoiceClipSheetState();
}

class _VoiceClipSheetState extends State<VoiceClipSheet> {
  final _player = AudioPlayer();
  late final _steady = NexSteadyPosition(_player);
  StreamSubscription<PlayerState>? _ended;
  Duration _total = Duration.zero;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _total = Duration(milliseconds: widget.attachment.durationMs ?? 0);
    // At the end: back to the start, with Play on the button.
    _ended = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && state.playing) {
        unawaited(_steady.rewind());
      }
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final length = await _player.setFilePath(widget.attachment.mediaUri);
      if (!mounted) return;
      if (length != null && length > Duration.zero) {
        setState(() => _total = length);
      }
      unawaited(_player.play());
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    unawaited(_ended?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  String _clock(Duration value, bool persian) {
    final seconds = value.inSeconds;
    return nexDigits(
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
      persian: persian,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = l10n.localeName == 'fa';
    final caption = widget.attachment.caption?.trim() ?? '';
    final said = widget.attachment.transcriptText?.trim() ?? '';
    return NexSheetBody(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NexSpacing.lg,
          NexSpacing.sm,
          NexSpacing.lg,
          NexSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              caption.isEmpty ? l10n.attachVoice : caption,
              style: theme.textTheme.titleMedium,
              textDirection: caption.isEmpty ? null : nexDirectionOf(caption),
            ),
            const SizedBox(height: NexSpacing.md),
            if (_failed)
              Text(l10n.mediaUnavailable, style: theme.textTheme.bodyMedium)
            else
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, state) {
                  final playing =
                      (state.data?.playing ?? false) &&
                      state.data?.processingState != ProcessingState.completed;
                  return Row(
                    children: [
                      IconButton.filled(
                        key: const ValueKey('voice-clip-play'),
                        iconSize: 32,
                        tooltip: playing
                            ? l10n.vaultAttachPause
                            : l10n.vaultAttachPlay,
                        onPressed: () async {
                          if (playing) {
                            await _player.pause();
                          } else {
                            await _steady.play();
                          }
                        },
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      ),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: StreamBuilder<Duration>(
                          stream: _player.positionStream,
                          builder: (context, position) {
                            final at = _steady.of(
                              position.data ?? Duration.zero,
                            );
                            final whole = _total.inMilliseconds;
                            final fraction = whole <= 0
                                ? 0.0
                                : (at.inMilliseconds / whole).clamp(0.0, 1.0);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    NexRadius.pill,
                                  ),
                                  child: LinearProgressIndicator(
                                    value: fraction,
                                    minHeight: 6,
                                    backgroundColor: scheme.primary.withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: NexSpacing.xs),
                                Row(
                                  children: [
                                    Text(
                                      _clock(at, persian),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                    const Spacer(),
                                    Text(
                                      _clock(_total, persian),
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            if (said.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.md),
              Text(
                said,
                textDirection: nexDirectionOf(said),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
