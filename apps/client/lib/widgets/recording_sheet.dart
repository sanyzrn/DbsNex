import 'dart:async';


import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:record/record.dart';
import '../l10n/app_localizations.dart';

/// The live recording surface.
///
/// A pulsing dot said only "something is happening". A waveform that scrolls
/// with the voice says the microphone is hearing *you* — which is the one thing
/// a person needs to know before they have any recording to play back. It is
/// also what 05-design.md asks for: continuous, functional motion, not decoration.
class RecordingSheet extends StatefulWidget {
  const RecordingSheet({super.key, required this.recorder});

  final AudioRecorder recorder;

  @override
  State<RecordingSheet> createState() => _RecordingSheetState();
}

class _RecordingSheetState extends State<RecordingSheet> {
  static const _barCount = 48;

  final watch = Stopwatch()..start();
  Timer? timer;
  StreamSubscription<Amplitude>? amplitudeSub;

  /// Oldest first. Seeded flat so the waveform has a baseline to grow from
  /// rather than filling in from an empty left edge.
  final List<double> _levels = List<double>.filled(_barCount, 0.04, growable: true);

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => setState(() {}),
    );
    amplitudeSub = widget.recorder
        .onAmplitudeChanged(const Duration(milliseconds: 60))
        .listen((value) {
      if (!mounted) return;
      // `current` is dBFS: roughly -60 (silence) to 0 (clipping). Squared so
      // ordinary speech uses more of the range than a linear map gives it.
      final normalized = ((value.current + 60) / 60).clamp(0.0, 1.0);
      setState(() {
        _levels
          ..add(0.04 + 0.96 * (normalized * normalized))
          ..removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    amplitudeSub?.cancel();
    watch.stop();
    super.dispose();
  }

  String get elapsed {
    final minutes = watch.elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds =
        watch.elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: true,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NexSpacing.lg,
            NexSpacing.md,
            NexSpacing.lg,
            NexSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RecordingDot(theme: theme),
                  const SizedBox(width: NexSpacing.sm),
                  Semantics(
                    liveRegion: true,
                    label: l10n.recordingElapsed(elapsed),
                    child: Text(
                      elapsed,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexSpacing.lg),
              SizedBox(
                height: 96,
                child: CustomPaint(
                  painter: _WaveformPainter(
                    // A copy: the painter compares against its previous
                    // levels, and the live list is mutated in place — the
                    // same instance would compare equal to itself and the
                    // waveform would never repaint.
                    levels: List.of(_levels),
                    color: theme.colorScheme.onSurface,
                  ),
                  size: Size.infinite,
                ),
              ),
              const SizedBox(height: NexSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.secondary,
                        padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
                      ),
                      child: Text(l10n.discard),
                    ),
                  ),
                  const SizedBox(width: NexSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
                      ),
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(l10n.stopRecording),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The steady "we are recording" pulse, independent of what the mic hears.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot({required this.theme});

  final ThemeData theme;

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_pulse.isAnimating) _pulse.stop();
      return _dot(1);
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => _dot(0.45 + 0.55 * _pulse.value),
    );
  }

  Widget _dot(double opacity) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: NexColors.swipeDelete.withValues(alpha: opacity),
        ),
      );
}

/// Draws the amplitude history as mirrored bars, newest at the right.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final slot = size.width / levels.length;
    final barWidth = (slot * 0.55).clamp(2.0, 6.0);
    final middle = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < levels.length; i++) {
      // Older samples fade out, so the eye follows the live edge.
      final age = i / levels.length;
      paint.color = color.withValues(alpha: 0.25 + 0.75 * age);
      final half = (levels[i] * middle).clamp(1.5, middle);
      final x = slot * i + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, middle - half, barWidth, half * 2),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      !listEquals(oldDelegate.levels, levels) || oldDelegate.color != color;
}
