import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pause_patterns.dart';

/// The colours of a mode: a dusk sky, deep at the top and lit at the bottom.
class PausePalette {
  const PausePalette(this.top, this.middle, this.glow, this.floor);

  final Color top;
  final Color middle;
  final Color glow;
  final Color floor;

  static PausePalette of(PauseMode mode) => switch (mode) {
    PauseMode.calm => const PausePalette(
      Color(0xFF1E2333),
      Color(0xFF1B2A55),
      Color(0xFF5B63B8),
      Color(0xFF9A9AA8),
    ),
    PauseMode.focus => const PausePalette(
      Color(0xFF16232A),
      Color(0xFF123F4A),
      Color(0xFF2E8C8C),
      Color(0xFF8FA6A3),
    ),
    PauseMode.relax => const PausePalette(
      Color(0xFF241D2E),
      Color(0xFF3B2550),
      Color(0xFF9A5C9E),
      Color(0xFFB09AA6),
    ),
  };
}

/// The sky behind a session or a card. The light at the bottom rises a
/// little as the lungs fill and sinks as they empty.
class PauseSkyPainter extends CustomPainter {
  const PauseSkyPainter({required this.palette, required this.fullness});

  final PausePalette palette;
  final double fullness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.top, palette.middle, palette.glow, palette.floor],
          stops: [0, 0.38 - 0.06 * fullness, 0.74 - 0.08 * fullness, 1],
        ).createShader(rect),
    );
    // A soft bloom, wider with a full breath.
    final center = Offset(size.width * 0.5, size.height * 0.62);
    canvas.drawCircle(
      center,
      size.shortestSide * (0.45 + 0.2 * fullness),
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                palette.glow.withValues(alpha: 0.28 + 0.12 * fullness),
                palette.glow.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: center,
                radius: size.shortestSide * (0.45 + 0.2 * fullness),
              ),
            ),
    );
  }

  @override
  bool shouldRepaint(PauseSkyPainter old) =>
      old.fullness != fullness || old.palette != palette;
}

/// The line drawing at the centre of a mode, at a given fullness.
///
/// [seconds] is the session's clock, for the one motion that is not the
/// breath: Relax's globe turning.
class PauseArtPainter extends CustomPainter {
  const PauseArtPainter({
    required this.mode,
    required this.fullness,
    this.seconds = 0,
    this.color = Colors.white,
    this.stroke = 1.6,
  });

  final PauseMode mode;
  final double fullness;
  final double seconds;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    switch (mode) {
      case PauseMode.calm:
        _calm(canvas, center, r, paint);
      case PauseMode.focus:
        _focus(canvas, center, r, paint);
      case PauseMode.relax:
        _relax(canvas, center, r, paint);
    }
  }

  /// Eight strokes round a ring. Empty, each is a short line pointing at the
  /// centre; breathing in, they open one after another, clockwise from the
  /// top, into circles — and close again, in the same order, on the way out.
  void _calm(Canvas canvas, Offset c, double r, Paint paint) {
    const count = 8;
    const spread = 0.9;
    final ring = r * (0.62 + 0.08 * fullness);
    final length = r * 0.3;
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / count;
      final open = ((fullness * (1 + spread) - spread * i / (count - 1))).clamp(
        0.0,
        1.0,
      );
      final width = length * pauseEase(open);
      final at = c + Offset(math.cos(angle), math.sin(angle)) * ring;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      if (width < 0.6) {
        canvas.drawLine(Offset(-length / 2, 0), Offset(length / 2, 0), paint);
      } else {
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: length, height: width),
          paint,
        );
      }
      canvas.restore();
    }
  }

  /// Six ellipses sharing a top and a bottom, like the lines of a globe seen
  /// from the side. Breathing in fans them out; breathing out folds them
  /// back into one.
  void _focus(Canvas canvas, Offset c, double r, Paint paint) {
    const count = 6;
    final height = r * 1.3;
    final fan = 0.12 + 0.88 * fullness;
    for (var k = 0; k < count; k++) {
      final width = height * (0.42 + (k / (count - 1)) * 0.92 * fan);
      canvas.drawOval(
        Rect.fromCenter(center: c, width: width, height: height),
        paint,
      );
    }
  }

  /// A globe: a circle and three meridians turning slowly, the whole of it
  /// growing with the breath.
  void _relax(Canvas canvas, Offset c, double r, Paint paint) {
    final radius = r * (0.52 + 0.18 * fullness);
    canvas.drawCircle(c, radius, paint);
    const meridians = 3;
    final turn = seconds * 0.35;
    for (var k = 0; k < meridians; k++) {
      final theta = turn + k * math.pi / meridians;
      final half = radius * math.cos(theta).abs();
      if (half < 0.8) {
        canvas.drawLine(c - Offset(0, radius), c + Offset(0, radius), paint);
        continue;
      }
      canvas.drawOval(
        Rect.fromCenter(center: c, width: half * 2, height: radius * 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(PauseArtPainter old) =>
      old.fullness != fullness ||
      old.seconds != seconds ||
      old.mode != mode ||
      old.color != color;
}

/// A mode's card, still: the sky and its drawing as each one is best seen.
class PauseModeArt extends StatelessWidget {
  const PauseModeArt({super.key, required this.mode});

  final PauseMode mode;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: PauseSkyPainter(palette: PausePalette.of(mode), fullness: 0.5),
    foregroundPainter: PauseArtPainter(
      mode: mode,
      fullness: switch (mode) {
        PauseMode.calm => 0,
        PauseMode.focus => 1,
        PauseMode.relax => 1,
      },
      seconds: 0.6,
    ),
  );
}
