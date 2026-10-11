import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';
import 'cycle_today.dart';

/// The cycle as a ring: the period at its start in rose, the fertile window
/// in teal, and a dot for today that travels round as the days go.
///
/// A circle because a cycle is one — the next period is where the ring
/// closes — and because "how far round" is read at a glance where a number
/// of days has to be read.
///
/// It can be touched: a finger on the ring, or drawn round it, shows that
/// day — its date, its day of the cycle and its stage — with a second
/// marker where the finger is. A touch in the middle comes back to today.
class CycleRing extends StatefulWidget {
  const CycleRing({
    super.key,
    required this.prediction,
    required this.headline,
    required this.caption,
    this.solar = false,
  });

  final CyclePrediction prediction;
  final String headline;
  final String caption;
  final bool solar;

  @override
  State<CycleRing> createState() => _CycleRingState();
}

class _CycleRingState extends State<CycleRing> {
  /// The day looked at, from 0 on the day the cycle began; null for today.
  int? _picked;

  int get _length =>
      math.max(widget.prediction.averageCycle, widget.prediction.cycleDay);

  void _touch(Offset at, Size size) {
    final center = size.center(Offset.zero);
    final offset = at - center;
    // The middle is the way back to today.
    if (offset.distance < size.shortestSide * 0.28) {
      if (_picked != null) setState(() => _picked = null);
      return;
    }
    // Clockwise from the top, as the ring is drawn.
    var angle = math.atan2(offset.dy, offset.dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final index = (angle / (math.pi * 2) * _length).floor().clamp(
      0,
      _length - 1,
    );
    if (index != _picked) {
      HapticFeedback.selectionClick();
      setState(() => _picked = index);
    }
  }

  @override
  void didUpdateWidget(CycleRing old) {
    super.didUpdateWidget(old);
    if (old.prediction.lastStart != widget.prediction.lastStart) {
      _picked = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final p = widget.prediction;
    final length = _length;
    final fertileFrom = p.fertile.start.daysSince(p.lastStart);
    final fertileTo = p.fertile.end.daysSince(p.lastStart) + 1;
    final progress = (p.cycleDay - 0.5) / length;
    final picked = _picked;
    final day = p.lastStart.addDays(picked ?? p.cycleDay - 1);
    final stage = p.stageOn(day);
    final stageColor = cycleStageColor(stage, brightness);
    final about = l10n.cycleStageAbout(
      cycleStageLabel(l10n, stage),
      cycleDigits(context, (picked ?? p.cycleDay - 1) + 1),
    );
    final headline = picked == null
        ? widget.headline
        : cycleDayMonth(context, day.local, solar: widget.solar);
    return Semantics(
      label: '$headline. ${widget.caption}. $about',
      hint: l10n.cycleRingHint,
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _touch(d.localPosition, size),
              onPanStart: (d) => _touch(d.localPosition, size),
              onPanUpdate: (d) => _touch(d.localPosition, size),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  painter: _RingPainter(
                    track: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                    period: cyclePeriodColor(brightness),
                    periodEnd: cycleMauve(brightness),
                    fertile: cycleFertileColor(brightness),
                    marker: Colors.white,
                    periodFraction: p.averagePeriod / length,
                    fertileFrom: fertileFrom / length,
                    fertileTo: fertileTo / length,
                    progress: t,
                    picked: picked == null ? null : (picked + 0.5) / length,
                    pickedColor: stageColor,
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(
                        NexSpacing.xl + NexSpacing.md,
                      ),
                      // Shrunk to fit inside the ring rather than spilling
                      // over it at the largest text sizes (LOC-04).
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
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
                            if (picked == null)
                              Text(
                                widget.caption,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: NexSpacing.xs),
                            DecoratedBox(
                              key: const ValueKey('cycle-ring-stage'),
                              decoration: BoxDecoration(
                                color: stageColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(
                                  NexRadius.xl,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: NexSpacing.sm,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      cycleStageIcon(stage),
                                      size: 14,
                                      color: stageColor,
                                    ),
                                    const SizedBox(width: NexSpacing.xs),
                                    Text(
                                      about,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: stageColor),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (picked != null) ...[
                              const SizedBox(height: NexSpacing.xs),
                              Text(
                                l10n.cycleRingBack,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.track,
    required this.period,
    required this.periodEnd,
    required this.fertile,
    required this.marker,
    required this.periodFraction,
    required this.fertileFrom,
    required this.fertileTo,
    required this.progress,
    this.picked,
    this.pickedColor,
  });

  final Color track, period, periodEnd, fertile, marker;
  final double periodFraction, fertileFrom, fertileTo, progress;

  /// Where a finger has picked a day, as a fraction of the ring; null when
  /// none has.
  final double? picked;
  final Color? pickedColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.06;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2 - stroke,
    );
    const start = -math.pi / 2;
    const full = math.pi * 2;

    // A soft light in the middle, so the words sit in a glow rather than
    // on a hole.
    canvas.drawCircle(
      rect.center,
      rect.width / 2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            period.withValues(alpha: 0.10),
            periodEnd.withValues(alpha: 0.04),
            period.withValues(alpha: 0),
          ],
          stops: const [0, 0.7, 1],
        ).createShader(rect),
    );
    canvas.drawArc(
      rect,
      0,
      full,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    // Each arc twice: blurred underneath for its glow, then itself — a
    // gradient along its own length, so it reads as light, not as paint.
    void arc(double from, double sweep, Color a, Color b) {
      if (sweep <= 0) return;
      Shader along(Color a, Color b) => SweepGradient(
        endAngle: sweep,
        colors: [a, b],
        transform: GradientRotation(from),
      ).createShader(rect);
      final shader = along(a, b);
      canvas.drawArc(
        rect,
        from,
        sweep,
        false,
        Paint()
          ..shader = along(a.withValues(alpha: 0.4), b.withValues(alpha: 0.4))
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.8),
      );
      canvas.drawArc(
        rect,
        from,
        sweep,
        false,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    arc(start, full * periodFraction.clamp(0.02, 1.0), period, periodEnd);
    if (fertileTo > fertileFrom && fertileFrom >= 0 && fertileTo <= 1.0) {
      arc(
        start + full * fertileFrom,
        full * (fertileTo - fertileFrom),
        fertile.withValues(alpha: 0.75),
        fertile,
      );
    }
    // Today: a pearl riding the ring, with a halo of rose round it.
    final angle = start + full * progress;
    final at =
        rect.center +
        Offset(math.cos(angle), math.sin(angle)) * (rect.width / 2);
    canvas.drawCircle(
      at,
      stroke * 1.2,
      Paint()
        ..color = period.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.7),
    );
    canvas.drawCircle(at, stroke * 0.72, Paint()..color = marker);
    canvas.drawCircle(at, stroke * 0.36, Paint()..color = period);
    // The day a finger is on: a ring of its stage's colour, open in the
    // middle so it never hides today's pearl.
    if (picked case final f?) {
      final a = start + full * f;
      final p =
          rect.center + Offset(math.cos(a), math.sin(a)) * (rect.width / 2);
      canvas.drawCircle(p, stroke * 0.9, Paint()..color = marker);
      canvas.drawCircle(
        p,
        stroke * 0.9,
        Paint()
          ..color = pickedColor ?? period
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.35,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.period != period ||
      old.periodEnd != periodEnd ||
      old.fertile != fertile ||
      old.periodFraction != periodFraction ||
      old.fertileFrom != fertileFrom ||
      old.fertileTo != fertileTo ||
      old.picked != picked ||
      old.pickedColor != pickedColor;
}

/// One arc for how far along something is — the forty weeks of a
/// pregnancy — with words in the middle, matching [CycleRing].
class CycleProgressRing extends StatelessWidget {
  const CycleProgressRing({
    super.key,
    required this.fraction,
    required this.color,
    required this.headline,
    required this.caption,
  });

  final double fraction;
  final Color color;
  final String headline;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$headline. $caption',
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            painter: _RingPainter(
              track: theme.colorScheme.onSurface.withValues(alpha: 0.07),
              period: color,
              periodEnd: cycleMauve(theme.brightness),
              fertile: Colors.transparent,
              marker: Colors.white,
              periodFraction: t,
              fertileFrom: 0,
              fertileTo: 0,
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
