/// The look of Habits 2.0 (2.4.0): each habit's own mark and colour, the
/// ring a day fills, the chain of its last days and the heat map of its
/// season. Colour tells habits apart; the shapes say what happened, so a
/// state never rests on colour alone.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';

/// The marks a habit can wear, by the id stored in its record.
const habitIcons = <String, IconData>{
  'spark': Icons.auto_awesome_rounded,
  'water': Icons.water_drop_rounded,
  'book': Icons.menu_book_rounded,
  'walk': Icons.directions_walk_rounded,
  'run': Icons.directions_run_rounded,
  'gym': Icons.fitness_center_rounded,
  'stretch': Icons.self_improvement_rounded,
  'sleep': Icons.bedtime_rounded,
  'food': Icons.eco_rounded,
  'language': Icons.translate_rounded,
  'write': Icons.edit_note_rounded,
  'music': Icons.music_note_rounded,
  'code': Icons.code_rounded,
  'screen': Icons.phonelink_erase_rounded,
  'sun': Icons.wb_sunny_rounded,
  'heart': Icons.favorite_rounded,
  'pill': Icons.medication_rounded,
  'tidy': Icons.cleaning_services_rounded,
  'save': Icons.savings_rounded,
  'plant': Icons.local_florist_rounded,
};

/// A habit's colour: [base] for marks and fills, [deep] behind white words.
typedef HabitHue = ({Color base, Color deep});

/// The eight colours a habit can take, by the index stored in its record.
const habitHues = <HabitHue>[
  (base: Color(0xFF14B8A6), deep: Color(0xFF0F766E)), // teal
  (base: Color(0xFF6366F1), deep: Color(0xFF4338CA)), // indigo
  (base: Color(0xFFF43F5E), deep: Color(0xFFBE123C)), // rose
  (base: Color(0xFFF59E0B), deep: Color(0xFFB45309)), // amber
  (base: Color(0xFF10B981), deep: Color(0xFF047857)), // green
  (base: Color(0xFF0EA5E9), deep: Color(0xFF0369A1)), // sky
  (base: Color(0xFFA855F7), deep: Color(0xFF7E22CE)), // violet
  (base: Color(0xFFF97316), deep: Color(0xFFC2410C)), // orange
];

HabitHue habitHueOf(Habit habit) =>
    habitHues[habit.hue.clamp(0, habitHues.length - 1)];

IconData habitIconOf(Habit habit) =>
    habitIcons[habit.icon] ?? Icons.auto_awesome_rounded;

/// The habit's colour against the page: its own in light, a touch lighter
/// in dark so it never sinks into the surface.
Color habitColor(BuildContext context, Habit habit) {
  final hue = habitHueOf(habit).base;
  return Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(hue, Colors.white, 0.12)!
      : hue;
}

/// A ring that fills clockwise from the top (anticlockwise in right to
/// left), with [child] in its middle.
class HabitRing extends StatelessWidget {
  const HabitRing({
    super.key,
    required this.progress,
    required this.color,
    this.track,
    this.size = 48,
    this.stroke = 4,
    this.child,
  });

  /// 0–1.
  final double progress;
  final Color color;
  final Color? track;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: NexMotion.of(context, NexMotion.morph),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => CustomPaint(
        painter: _RingPainter(
          progress: value,
          color: color,
          track: track ?? scheme.outlineVariant.withValues(alpha: 0.6),
          stroke: stroke,
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
        child: child,
      ),
      child: SizedBox.square(
        dimension: size,
        // Large text shrinks to fit the ring rather than spilling out of it.
        child: Padding(
          padding: EdgeInsets.all(stroke + 2),
          child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
    required this.rtl,
  });

  final double progress;
  final Color color;
  final Color track;
  final double stroke;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    if (progress <= 0) return;
    final sweep = math.pi * 2 * progress;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      rtl ? -sweep : sweep,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.rtl != rtl;
}

/// One piece of the day ring: a habit due today and how far along it is.
typedef HabitDayPiece = ({Color color, double progress});

/// Today's ring: one arc for each habit due today, in its own colour,
/// filling as it is kept — the day's shape at a glance.
class HabitDayRing extends StatelessWidget {
  const HabitDayRing({
    super.key,
    required this.pieces,
    this.size = 112,
    this.child,
  });

  final List<HabitDayPiece> pieces;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final track = Colors.white.withValues(alpha: 0.22);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: NexMotion.of(context, NexMotion.receipt),
      curve: Curves.easeOutCubic,
      builder: (context, grow, child) => CustomPaint(
        painter: _DayRingPainter(
          pieces: pieces,
          track: track,
          grow: grow,
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
        child: child,
      ),
      child: SizedBox.square(
        dimension: size,
        // Large text shrinks to fit the ring rather than spilling out of it.
        child: Padding(
          padding: EdgeInsets.all(size * 0.16),
          child: Center(
            child: FittedBox(fit: BoxFit.scaleDown, child: child),
          ),
        ),
      ),
    );
  }
}

class _DayRingPainter extends CustomPainter {
  _DayRingPainter({
    required this.pieces,
    required this.track,
    required this.grow,
    required this.rtl,
  });

  final List<HabitDayPiece> pieces;
  final Color track;
  final double grow;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (pieces.isEmpty) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
      return;
    }
    final n = pieces.length;
    // A gap between pieces wide enough for the round caps to stay apart.
    final gap = n == 1 ? 0.0 : (stroke * 1.6) / (rect.width / 2);
    final span = math.pi * 2 / n;
    final sign = rtl ? -1 : 1;
    for (final (i, piece) in pieces.indexed) {
      final start = -math.pi / 2 + sign * (i * span + gap / 2);
      final length = n == 1 ? math.pi * 2 : span - gap;
      canvas.drawArc(rect, start, sign * length, false, paint..color = track);
      final fill = length * piece.progress.clamp(0.0, 1.0) * grow;
      if (fill > 0) {
        canvas.drawArc(
          rect,
          start,
          sign * fill,
          false,
          paint..color = piece.color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DayRingPainter old) =>
      old.grow != grow ||
      old.rtl != rtl ||
      old.pieces.length != pieces.length ||
      [
        for (var i = 0; i < pieces.length; i++) old.pieces[i] != pieces[i],
      ].any((changed) => changed);
}

/// One day as a small mark: a filled dot kept, a half-filled one partly
/// kept, a hollow ring missed, a short dash a day off, and an outlined dot
/// today still to do.
class HabitDayMark extends StatelessWidget {
  const HabitDayMark({
    super.key,
    required this.state,
    required this.color,
    this.size = 12,
  });

  final HabitDayState state;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _DayMarkPainter(
          state: state,
          color: color,
          muted: scheme.outlineVariant,
          rtl: Directionality.of(context) == TextDirection.rtl,
        ),
      ),
    );
  }
}

class _DayMarkPainter extends CustomPainter {
  _DayMarkPainter({
    required this.state,
    required this.color,
    required this.muted,
    required this.rtl,
  });

  final HabitDayState state;
  final Color color;
  final Color muted;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, radius * 0.28);
    switch (state) {
      case HabitDayState.done:
        canvas.drawCircle(center, radius, fill..color = color);
      case HabitDayState.partial:
        canvas.drawCircle(
          center,
          radius - line.strokeWidth / 2,
          line..color = color,
        );
        canvas.drawArc(
          Offset.zero & size,
          math.pi / 2,
          rtl ? -math.pi : math.pi,
          true,
          fill..color = color,
        );
      case HabitDayState.missed:
        canvas.drawCircle(
          center,
          radius - line.strokeWidth / 2,
          line..color = muted,
        );
      case HabitDayState.pending:
        canvas.drawCircle(
          center,
          radius - line.strokeWidth / 2,
          line..color = color,
        );
      case HabitDayState.off:
        canvas.drawLine(
          center.translate(-radius * 0.45, 0),
          center.translate(radius * 0.45, 0),
          line
            ..color = muted
            ..strokeCap = StrokeCap.round,
        );
      case HabitDayState.future:
        canvas.drawCircle(center, radius * 0.18, fill..color = muted);
    }
  }

  @override
  bool shouldRepaint(_DayMarkPainter old) =>
      old.state != state ||
      old.color != color ||
      old.muted != muted ||
      old.rtl != rtl;
}

/// The habit's last seven days as a chain of marks, oldest first, today
/// last.
class HabitChain extends StatelessWidget {
  const HabitChain({
    super.key,
    required this.habit,
    required this.logged,
    required this.color,
    this.days = 7,
  });

  final Habit habit;
  final Map<DateTime, int> logged;
  final Color color;
  final int days;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = days - 1; i >= 0; i--)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 3),
              child: HabitDayMark(
                size: 9,
                color: color,
                state: HabitMath.dayState(
                  habit,
                  DateTime(now.year, now.month, now.day - i),
                  logged,
                  now,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The last [weeks] weeks as columns of seven days, today's week last —
/// the season of a habit in one picture.
class HabitHeatmap extends StatelessWidget {
  const HabitHeatmap({
    super.key,
    required this.habit,
    required this.logged,
    required this.color,
    required this.firstDay,
    this.weeks = 16,
  });

  final Habit habit;
  final Map<DateTime, int> logged;
  final Color color;
  final int firstDay;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final lastWeek = HabitMath.weekStartOf(today, firstDay: firstDay);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        final cell = ((constraints.maxWidth - gap * (weeks - 1)) / weeks).clamp(
          6.0,
          16.0,
        );
        return ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var w = weeks - 1; w >= 0; w--)
                Padding(
                  padding: EdgeInsetsDirectional.only(end: w == 0 ? 0 : gap),
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Padding(
                          padding: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                          child: HabitDayMark(
                            size: cell,
                            color: color,
                            state: HabitMath.dayState(
                              habit,
                              lastWeek.subtract(Duration(days: 7 * w - d)),
                              logged,
                              now,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The key to the marks, for the heat map and the calendar.
class HabitMarkLegend extends StatelessWidget {
  const HabitMarkLegend({super.key, required this.color, required this.labels});

  final Color color;

  /// Done, partly, missed, day off — in that order.
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const states = [
      HabitDayState.done,
      HabitDayState.partial,
      HabitDayState.missed,
      HabitDayState.off,
    ];
    return Wrap(
      spacing: NexSpacing.md,
      runSpacing: NexSpacing.xs,
      children: [
        for (final (i, state) in states.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HabitDayMark(state: state, color: color, size: 10),
              const SizedBox(width: NexSpacing.xs),
              Text(
                labels[i],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}