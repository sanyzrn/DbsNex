import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_dialog.dart';
import 'steady_position.dart';
import 'voice_player.dart';

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
  bool _ready = false;

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
      setState(() {
        _ready = true;
        if (length != null && length > Duration.zero) _total = length;
      });
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
              NexVoicePlayer(
                path: widget.attachment.mediaUri,
                steady: _ready ? _steady : null,
                length: _total,
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
