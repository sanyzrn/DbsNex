import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A faint motif along the bottom of the screen, for the themes that have
/// one.
///
/// Not a background pattern: those covered the whole page and were retired
/// for whole-app themes. This is a detail of a theme — paper fibre on
/// Paper, tile stars on Isfahan turquoise — kept to the lower part of the
/// screen, fading out as it rises, and drawn at a few percent of the text
/// colour, so it is felt more than seen and never sits behind the words at
/// the top of the timeline.
enum NexThemeTexture { none, fibre, girih, contours, waves, stars }

/// Paints [texture] behind [child], in the lower [extent] of the box.
class NexTextureBackdrop extends StatelessWidget {
  const NexTextureBackdrop({
    super.key,
    required this.texture,
    required this.child,
    this.extent = 0.36,
  });

  final NexThemeTexture texture;
  final Widget child;

  /// How much of the height, from the bottom, the motif occupies.
  final double extent;

  @override
  Widget build(BuildContext context) {
    if (texture == NexThemeTexture.none) return child;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface.withValues(
      alpha: dark ? 0.13 : 0.10,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: NexTexturePainter(
                texture: texture,
                ink: ink,
                extent: extent,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The motif itself. Public for the theme picker's previews.
class NexTexturePainter extends CustomPainter {
  NexTexturePainter({
    required this.texture,
    required this.ink,
    this.extent = 0.36,
  });

  final NexThemeTexture texture;
  final Color ink;
  final double extent;

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == NexThemeTexture.none || size.isEmpty) return;
    final band = Rect.fromLTWH(
      0,
      size.height * (1 - extent),
      size.width,
      size.height * extent,
    );
    // Drawn into a layer and faded upward through a mask, so the motif has
    // no top edge: it is there at the bottom and simply is not at the top.
    canvas.saveLayer(band, Paint());
    canvas.clipRect(band);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    switch (texture) {
      case NexThemeTexture.none:
        break;
      case NexThemeTexture.fibre:
        _fibre(canvas, band, stroke);
      case NexThemeTexture.girih:
        _girih(canvas, band, stroke);
      case NexThemeTexture.contours:
        _contours(canvas, band, stroke);
      case NexThemeTexture.waves:
        _waves(canvas, band, stroke);
      case NexThemeTexture.stars:
        _stars(canvas, band, Paint()..color = ink);
    }
    canvas.drawRect(
      band,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x00000000), Color(0xFF000000)],
          // Full strength over the lower part of the band, not only at the
          // very bottom edge, where the navigation bar covers it.
          stops: const [0, 0.6],
        ).createShader(band),
    );
    canvas.restore();
  }

  /// Short, uneven strokes, mostly level: the grain of laid paper.
  static void _fibre(Canvas canvas, Rect band, Paint stroke) {
    final random = math.Random(7);
    stroke.strokeWidth = 0.8;
    for (var y = band.top; y < band.bottom; y += 5) {
      var x = band.left - random.nextDouble() * 40;
      while (x < band.right) {
        final length = 8 + random.nextDouble() * 34;
        final tilt = (random.nextDouble() - 0.5) * 2;
        canvas.drawLine(Offset(x, y), Offset(x + length, y + tilt), stroke);
        x += length + 6 + random.nextDouble() * 22;
      }
    }
  }

  /// Eight-pointed stars on a square grid, the commonest figure in the
  /// tilework of Isfahan, with the lines that join them.
  static void _girih(Canvas canvas, Rect band, Paint stroke) {
    const cell = 44.0;
    const r = cell * 0.3;
    final star = Path();
    for (var i = 0; i < 16; i++) {
      final radius = i.isEven ? r : r * 0.62;
      final angle = i * math.pi / 8 - math.pi / 2;
      final point = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    final top = band.top - (band.top % cell);
    for (var y = top; y < band.bottom + cell; y += cell) {
      for (var x = band.left; x < band.right + cell; x += cell) {
        canvas.drawPath(star.shift(Offset(x, y)), stroke);
        canvas.drawLine(Offset(x + r, y), Offset(x + cell - r, y), stroke);
        canvas.drawLine(Offset(x, y + r), Offset(x, y + cell - r), stroke);
      }
    }
  }

  /// The contour lines of a map: nested, gently wandering curves.
  static void _contours(Canvas canvas, Rect band, Paint stroke) {
    for (var i = 0; i < 14; i++) {
      final base = band.top + i * band.height / 12;
      final path = Path()..moveTo(band.left, base);
      for (var x = band.left; x <= band.right; x += 8) {
        final t = x / math.max(band.width, 1);
        final y =
            base +
            math.sin(t * math.pi * 2.2 + i * 0.6) * 10 +
            math.sin(t * math.pi * 5.1 + i * 1.3) * 4;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, stroke);
    }
  }

  /// Rows of long, low waves.
  static void _waves(Canvas canvas, Rect band, Paint stroke) {
    for (var row = 0; row * 14.0 < band.height + 14; row++) {
      final base = band.top + row * 14.0;
      final shift = row.isEven ? 0.0 : 18.0;
      final path = Path()..moveTo(band.left - 36, base);
      for (var x = band.left - 36 + shift; x < band.right + 36; x += 36) {
        path.quadraticBezierTo(x + 9, base - 5, x + 18, base);
        path.quadraticBezierTo(x + 27, base + 5, x + 36, base);
      }
      canvas.drawPath(path, stroke);
    }
  }

  /// A scatter of small stars, a few of them brighter.
  static void _stars(Canvas canvas, Rect band, Paint fill) {
    final random = math.Random(11);
    final count = (band.width * band.height / 900).round();
    for (var i = 0; i < count; i++) {
      final at = Offset(
        band.left + random.nextDouble() * band.width,
        band.top + random.nextDouble() * band.height,
      );
      final bright = random.nextDouble() < 0.12;
      canvas.drawCircle(at, bright ? 1.6 : 0.8, fill);
    }
  }

  @override
  bool shouldRepaint(NexTexturePainter old) =>
      old.texture != texture || old.ink != ink || old.extent != extent;
}
