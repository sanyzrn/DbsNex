import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'cycle_format.dart';

/// The cycle as a ring: the period at its start in rose, the fertile window
/// in teal, and a dot for today that travels round as the days go.
///
/// A circle because a cycle is one — the next period is where the ring
/// closes — and because "how far round" is read at a glance where a number
/// of days has to be read.
class CycleRing extends StatelessWidget {
  const CycleRing({
    super.key,
    required this.prediction,
    required this.headline,
    required this.caption,
  });

  final CyclePrediction prediction;
  final String headline;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final p = prediction;
    final length = math.max(p.averageCycle, p.cycleDay);
    final fertileFrom = p.fertile.start.daysSince(p.lastStart);
    final fertileTo = p.fertile.end.daysSince(p.lastStart) + 1;
    final progress = (p.cycleDay - 0.5) / length;
    return Semantics(
      label: '$headline. $caption',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            painter: _RingPainter(
              track: theme.colorScheme.surfaceContainerHighest,
              period: cyclePeriodColor(brightness),
              fertile: cycleFertileColor(brightness),
              marker: theme.colorScheme.onSurface,
              periodFraction: p.averagePeriod / length,
              fertileFrom: fertileFrom / length,
              fertileTo: fertileTo / length,
              progress: t,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(NexSpacing.xl + NexSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      headline,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.track,
    required this.period,
    required this.fertile,
    required this.marker,
    required this.periodFraction,
    required this.fertileFrom,
    required this.fertileTo,
    required this.progress,
  });

  final Color track, period, fertile, marker;
  final double periodFraction, fertileFrom, fertileTo, progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.075;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2 - 4,
    );
    const start = -math.pi / 2;
    const full = math.pi * 2;
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, full, false, arc(track));
    canvas.drawArc(
      rect,
      start,
      full * periodFraction.clamp(0.02, 1.0),
      false,
      arc(period),
    );
    if (fertileTo > fertileFrom && fertileFrom >= 0 && fertileTo <= 1.0) {
      canvas.drawArc(
        rect,
        start + full * fertileFrom,
        full * (fertileTo - fertileFrom),
        false,
        arc(fertile),
      );
    }
    // Today: a dot riding the ring, ringed in the page colour so it reads
    // on top of either arc.
    final angle = start + full * progress;
    final at =
        rect.center +
        Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
    canvas.drawCircle(at, stroke * 0.75, Paint()..color = track);
    canvas.drawCircle(at, stroke * 0.5, Paint()..color = marker);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.period != period ||
      old.fertile != fertile ||
      old.periodFraction != periodFraction ||
      old.fertileFrom != fertileFrom ||
      old.fertileTo != fertileTo;
}
