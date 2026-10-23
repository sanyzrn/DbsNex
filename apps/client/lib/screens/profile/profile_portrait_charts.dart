part of 'profile_portrait.dart';

/// The five traits as a shape: a web that fills outward from the middle as the
/// card arrives, so the whole portrait reads at a glance before the bars below
/// say each one in words.
class _TraitRadar extends StatelessWidget {
  const _TraitRadar({required this.traits, required this.slot});

  final List<NexPortraitTrait> traits;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entrance = _Entrance.of(context);
    final direction = Directionality.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 208,
        child: CustomPaint(
          painter: _RadarPainter(
            names: [for (final t in traits) t.name],
            scores: [for (final t in traits) (t.score / 100).clamp(0.0, 1.0)],
            clock: entrance,
            slot: slot,
            color: scheme.primary,
            grid: scheme.primary.withValues(alpha: 0.2),
            label: theme.textTheme.labelSmall!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            direction: direction,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.names,
    required this.scores,
    required this.clock,
    required this.slot,
    required this.color,
    required this.grid,
    required this.label,
    required this.direction,
  }) : super(repaint: clock);

  final List<String> names;
  final List<double> scores;
  final Animation<double> clock;
  final int slot;
  final Color color;
  final Color grid;
  final TextStyle label;
  final TextDirection direction;

  double get progress => _slice(clock.value, slot);

  /// The names, laid out once: they do not change while the web grows, and
  /// laying out text is the dear part of a frame here.
  List<TextPainter>? _labels;

  static const _labelWidth = 76.0;

  @override
  void paint(Canvas canvas, Size size) {
    final n = scores.length;
    if (n < 3) return;
    final center = size.center(Offset.zero);
    final radius = math.min(
      size.width / 2 - _labelWidth - 4,
      size.height / 2 - 24,
    );
    if (radius <= 0) return;
    Offset at(int i, double r) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      return center + Offset(math.cos(angle), math.sin(angle)) * r;
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;
    for (final step in const [1 / 3, 2 / 3, 1.0]) {
      final path = Path()
        ..moveTo(at(0, radius * step).dx, at(0, radius * step).dy);
      for (var i = 1; i < n; i++) {
        final p = at(i, radius * step);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), ring);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, at(i, radius), ring);
    }

    final shape = Path();
    for (var i = 0; i < n; i++) {
      final p = at(i, radius * scores[i] * progress);
      i == 0 ? shape.moveTo(p.dx, p.dy) : shape.lineTo(p.dx, p.dy);
    }
    shape.close();
    canvas.drawPath(
      shape,
      Paint()..color = color.withValues(alpha: 0.2 * progress),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: progress),
    );
    final dot = Paint()..color = color.withValues(alpha: progress);
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(at(i, radius * scores[i] * progress), 3.5, dot);
    }

    final labels = _labels ??= [
      for (final name in names)
        TextPainter(
          text: TextSpan(text: name, style: label),
          textDirection: direction,
          textAlign: TextAlign.center,
          maxLines: 2,
          ellipsis: '…',
        )..layout(maxWidth: _labelWidth),
    ];
    for (var i = 0; i < n; i++) {
      final text = labels[i];
      final tip = at(i, radius + 10);
      final cos = (tip.dx - center.dx) / (radius + 10);
      final sin = (tip.dy - center.dy) / (radius + 10);
      final dx = cos < -0.3
          ? tip.dx - text.width
          : cos > 0.3
          ? tip.dx
          : tip.dx - text.width / 2;
      final dy = sin < -0.5
          ? tip.dy - text.height
          : sin > 0.5
          ? tip.dy
          : tip.dy - text.height / 2;
      text.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.color != color || old.names != names || old.scores != scores;
}

/// The last 30 days as a row of bars, today on the end: tall where a lot was
/// written, a dot where nothing was. They rise one after another, a wave
/// running toward today.
class _Pulse extends StatelessWidget {
  const _Pulse({required this.days, required this.slot});

  final List<int> days;
  final int slot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entrance = _Entrance.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 56,
        child: CustomPaint(
          size: const Size.fromHeight(56),
          painter: _PulsePainter(
            days: days,
            clock: entrance,
            slot: slot,
            color: scheme.primary,
            rtl: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.days,
    required this.clock,
    required this.slot,
    required this.color,
    required this.rtl,
  }) : super(repaint: clock);

  final List<int> days;
  final Animation<double> clock;
  final int slot;
  double get progress => _slice(clock.value, slot);
  final Color color;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final n = days.length;
    if (n == 0) return;
    final most = days.fold<int>(1, math.max);
    const gap = 3.0;
    final width = (size.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      // Oldest first, so in a right-to-left page today sits at the left, where
      // the timeline of a Persian reader ends.
      final column = rtl ? n - 1 - i : i;
      final x = column * (width + gap);
      // A bar starts rising once the wave, sweeping 0→1 across the row, gets
      // to it, and takes a fifth of the sweep to get there.
      final local = ((progress * 1.25 - i / n * 0.5) / 0.5).clamp(0.0, 1.0);
      final eased = Curves.easeOutBack.transform(local).clamp(0.0, 1.2);
      final share = days[i] / most;
      final height = days[i] == 0 ? 3.0 : 6 + (size.height - 6) * share * eased;
      final today = i == n - 1;
      final paint = Paint()
        ..color = color.withValues(
          alpha: days[i] == 0
              ? 0.16
              : today
              ? 1
              : 0.28 + 0.5 * share,
        );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, width, height),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.days != days || old.color != color || old.rtl != rtl;
}

/// What the library is made of, as a ring that sweeps round once.
class _KindsDonut extends StatelessWidget {
  const _KindsDonut({
    required this.kinds,
    required this.tint,
    required this.slot,
    required this.total,
    required this.persian,
  });

  final List<(NoteType, int)> kinds;
  final Color Function(NoteType) tint;
  final int slot;
  final int total;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entrance = _Entrance.of(context);
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            child: CustomPaint(
              size: const Size(104, 104),
              painter: _DonutPainter(
                values: [for (final (_, count) in kinds) count.toDouble()],
                colors: [for (final (type, _) in kinds) tint(type)],
                track: scheme.primary.withValues(alpha: 0.1),
                clock: entrance,
                slot: slot,
              ),
            ),
          ),
          _CountUp(
            value: total,
            slot: slot,
            persian: persian,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.clock,
    required this.slot,
  }) : super(repaint: clock);

  final List<double> values;
  final List<Color> colors;
  final Color track;
  final Animation<double> clock;
  final int slot;
  double get progress => _slice(clock.value, slot);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    canvas.drawArc(
      arc,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final gap = values.length > 1 ? 0.05 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      canvas.drawArc(
        arc,
        start + gap / 2,
        math.max(0, sweep - gap) * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = colors[i],
      );
      start += sweep * progress;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.values != values || old.track != track;
}
