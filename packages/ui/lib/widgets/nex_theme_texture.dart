import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A faint motif rising from the bottom of the screen, for every theme but
/// the plain Nex one.
///
/// Not a background pattern: those covered the whole page and were retired
/// for whole-app themes. This is a detail of a theme — paper fibre on
/// Paper, tile stars on Isfahan turquoise, falling leaves on Autumn — kept to
/// the lower half of the screen, fading out as it rises, and drawn at a few
/// percent of the text colour, so it is felt more than seen and never sits
/// behind the words at the top of the timeline.
enum NexThemeTexture {
  none,
  fibre,
  girih,
  contours,
  waves,
  stars,
  leaves,
  petals,
  threads,
  grid,
  bauhaus,
  seams,
  circuit,
  halftone,
}

/// The new motifs use the selected theme's accent, keeping gold seams gold
/// and circuit traces cyan while established neutral textures stay unchanged.
bool nexTextureUsesAccent(NexThemeTexture texture) => const {
  NexThemeTexture.bauhaus,
  NexThemeTexture.seams,
  NexThemeTexture.circuit,
  NexThemeTexture.halftone,
}.contains(texture);

/// Paints [texture] behind [child], in the lower [extent] of the box.
class NexTextureBackdrop extends StatelessWidget {
  const NexTextureBackdrop({
    super.key,
    required this.texture,
    required this.child,
    this.extent = 0.5,
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
    final colored = nexTextureUsesAccent(texture);
    final ink =
        (colored ? theme.colorScheme.primary : theme.colorScheme.onSurface)
            .withValues(
              alpha: colored ? (dark ? 0.22 : 0.18) : (dark ? 0.13 : 0.10),
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
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
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
    this.extent = 0.5,
    this.pixelRatio,
  });

  final NexThemeTexture texture;
  final Color ink;
  final double extent;

  /// The device pixel ratio the motif is rasterized at.
  ///
  /// The motif is static — the whole point of it — so its picture is
  /// rasterized once into an image and each frame afterwards draws that
  /// image: one textured quad, under Impeller and Skia alike. Impeller has
  /// no raster cache to do this for a plain `CustomPainter`, so without this
  /// the fibre's ~860 strokes and its fading `saveLayer` were re-rasterized
  /// on every frame the screen moved — every frame of a scroll — which is
  /// why the plain Nex theme scrolled smoothly and the paper one did not.
  ///
  /// Null resolves the ratio from the view the painter runs in, which keeps
  /// a directly constructed painter working (the picker's previews, tests).
  final double? pixelRatio;

  double get _ratio =>
      pixelRatio ??
      ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ??
      1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (texture == NexThemeTexture.none || size.isEmpty) return;
    final ratio = _ratio;
    final image = nexRasterCachedImage(
      key: (
        'motif',
        texture,
        ink.toARGB32(),
        extent,
        (size.width * ratio).round(),
        (size.height * ratio).round(),
      ),
      size: size,
      pixelRatio: ratio,
      paint: _paintMotif,
    );
    if (image != null) {
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = ui.FilterQuality.none,
      );
      return;
    }
    // Nowhere to rasterize into (an unsupported platform, or the middle of a
    // teardown): the picture itself, exactly as this always painted.
    _paintMotif(canvas, size);
  }

  /// The motif as vector commands — the fallback, and the source the cached
  /// image is rasterized from, so both paths draw the same thing.
  void _paintMotif(Canvas canvas, Size size) {
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
        _stars(canvas, band, stroke, Paint()..color = ink);
      case NexThemeTexture.leaves:
        _leaves(canvas, band, stroke);
      case NexThemeTexture.petals:
        _petals(canvas, band, stroke);
      case NexThemeTexture.threads:
        _threads(canvas, band, stroke);
      case NexThemeTexture.grid:
        _grid(canvas, band, stroke);
      case NexThemeTexture.bauhaus:
        _bauhaus(canvas, band, stroke);
      case NexThemeTexture.seams:
        _seams(canvas, band, stroke);
      case NexThemeTexture.circuit:
        _circuit(canvas, band, stroke);
      case NexThemeTexture.halftone:
        _halftone(canvas, band, stroke);
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
          stops: const [0, 0.55],
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

  /// A scatter of small stars; the brightest few sparkle with four points,
  /// and two short constellations are joined up.
  static void _stars(Canvas canvas, Rect band, Paint stroke, Paint fill) {
    final random = math.Random(11);
    final count = (band.width * band.height / 900).round();
    final bright = <Offset>[];
    for (var i = 0; i < count; i++) {
      final at = Offset(
        band.left + random.nextDouble() * band.width,
        band.top + random.nextDouble() * band.height,
      );
      final roll = random.nextDouble();
      if (roll < 0.04) {
        bright.add(at);
        _sparkle(canvas, at, 3.5, fill);
      } else {
        canvas.drawCircle(at, roll < 0.16 ? 1.4 : 0.8, fill);
      }
    }
    // Each bright star to its nearest bright neighbour: a few short lines,
    // read as constellations rather than as a net.
    stroke.strokeWidth = 0.6;
    for (final a in bright.take(8)) {
      Offset? nearest;
      for (final b in bright) {
        if (b == a) continue;
        if (nearest == null || (b - a).distance < (nearest - a).distance) {
          nearest = b;
        }
      }
      if (nearest != null && (nearest - a).distance < 110) {
        canvas.drawLine(a, nearest, stroke);
      }
    }
    // And a thin crescent, low in the sky on the far side.
    final moon = Offset(
      band.left + band.width * 0.8,
      band.top + band.height * 0.42,
    );
    const r = 15.0;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: moon, radius: r)),
        Path()..addOval(
          Rect.fromCircle(
            center: moon + const Offset(r * 0.45, -r * 0.3),
            radius: r * 0.9,
          ),
        ),
      ),
      fill,
    );
  }

  static void _sparkle(Canvas canvas, Offset at, double r, Paint fill) {
    final path = Path()
      ..moveTo(at.dx, at.dy - r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
      ..close();
    canvas.drawPath(path, fill);
  }

  /// A point in [band], more often low than high — so leaves and petals
  /// gather towards the bottom, the way things that fall do.
  static Offset _settling(math.Random random, Rect band) => Offset(
    band.left + random.nextDouble() * band.width,
    band.top + math.sqrt(random.nextDouble()) * band.height,
  );

  /// Falling leaves: almond outlines with a midrib, each at its own angle.
  static void _leaves(Canvas canvas, Rect band, Paint stroke) {
    final random = math.Random(23);
    final count = (band.width * band.height / 6500).round();
    stroke.strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      final at = _settling(random, band);
      final size = 10 + random.nextDouble() * 9;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(random.nextDouble() * math.pi * 2);
      final leaf = Path()
        ..moveTo(0, -size)
        ..quadraticBezierTo(size * 0.75, 0, 0, size)
        ..quadraticBezierTo(-size * 0.75, 0, 0, -size)
        ..close();
      canvas.drawPath(leaf, stroke);
      // The midrib runs on past the leaf into its stalk.
      canvas.drawLine(Offset(0, -size * 0.7), Offset(0, size * 1.35), stroke);
      canvas.restore();
    }
  }

  /// Five-petalled blossoms, and loose petals drifting between them.
  static void _petals(Canvas canvas, Rect band, Paint stroke) {
    final random = math.Random(31);
    final count = (band.width * band.height / 7000).round();
    stroke.strokeWidth = 1;
    Path petal(double length) => Path()
      ..moveTo(0, 0)
      ..cubicTo(length * 0.5, -length * 0.45, length, -length * 0.2, length, 0)
      ..cubicTo(length, length * 0.2, length * 0.5, length * 0.45, 0, 0)
      ..close();
    for (var i = 0; i < count; i++) {
      final at = _settling(random, band);
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(random.nextDouble() * math.pi * 2);
      if (random.nextDouble() < 0.4) {
        final length = 11 + random.nextDouble() * 5;
        for (var k = 0; k < 5; k++) {
          canvas.drawPath(petal(length), stroke);
          canvas.rotate(math.pi * 2 / 5);
        }
        canvas.drawCircle(Offset.zero, 2.2, stroke);
      } else {
        canvas.drawPath(petal(8 + random.nextDouble() * 5), stroke);
      }
      canvas.restore();
    }
  }

  /// Saffron threads: three fine, curling stigmas from one point, scattered
  /// as if shaken from the jar.
  static void _threads(Canvas canvas, Rect band, Paint stroke) {
    final random = math.Random(41);
    final count = (band.width * band.height / 4200).round();
    stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final at = _settling(random, band);
      final base = random.nextDouble() * math.pi * 2;
      final strands = random.nextDouble() < 0.5 ? 3 : 1;
      for (var k = 0; k < strands; k++) {
        final angle = base + (k - 1) * 0.35;
        final length = 10 + random.nextDouble() * 9;
        final end =
            at + Offset(math.cos(angle) * length, math.sin(angle) * length);
        final bend = (random.nextDouble() - 0.5) * 8;
        final control =
            Offset.lerp(at, end, 0.5)! +
            Offset(-math.sin(angle) * bend, math.cos(angle) * bend);
        canvas.drawPath(
          Path()
            ..moveTo(at.dx, at.dy)
            ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy),
          stroke,
        );
        // The flared tip each thread ends in.
        canvas.drawCircle(end, 1.1, stroke);
      }
    }
  }

  /// Graph paper, for Graphite: a fine square grid with every fifth line a
  /// little stronger, as on an engineer's pad.
  static void _grid(Canvas canvas, Rect band, Paint stroke) {
    const cell = 14.0;
    final minor = Paint()
      ..color = stroke.color.withValues(alpha: stroke.color.a * 0.45)
      ..strokeWidth = 0.6;
    final major = Paint()
      ..color = stroke.color
      ..strokeWidth = 0.9;
    final top = band.top - (band.top % cell);
    var row = (band.top / cell).floor();
    for (var y = top; y <= band.bottom; y += cell, row++) {
      canvas.drawLine(
        Offset(band.left, y),
        Offset(band.right, y),
        row % 5 == 0 ? major : minor,
      );
    }
    var column = 0;
    for (var x = band.left; x <= band.right; x += cell, column++) {
      canvas.drawLine(
        Offset(x, band.top),
        Offset(x, band.bottom),
        column % 5 == 0 ? major : minor,
      );
    }
  }

  // Four static motifs. Bounded geometry, no blur, timer or animated shader.
  static void _bauhaus(Canvas canvas, Rect band, Paint stroke) {
    final unit = band.width / 4;
    final fill = Paint()..color = stroke.color;
    canvas.drawRect(
      Rect.fromLTWH(
        band.left - unit * .3,
        band.bottom - unit * 1.3,
        unit,
        unit * 1.3,
      ),
      fill,
    );
    canvas.drawCircle(
      Offset(band.right - unit * .6, band.bottom - unit * .6),
      unit * .8,
      stroke..strokeWidth = 2,
    );
    final path = Path()
      ..moveTo(band.center.dx - unit * .6, band.bottom)
      ..lineTo(band.center.dx + unit * .8, band.bottom)
      ..lineTo(band.center.dx + unit * .8, band.bottom - unit * 1.8)
      ..close();
    canvas.drawPath(path, fill);
    for (var i = 0; i < 5; i++) {
      final x = band.left + unit * .25 + i * unit * .18;
      canvas.drawLine(
        Offset(x, band.bottom - unit * 1.5),
        Offset(x, band.bottom - unit * 2.3),
        stroke,
      );
    }
  }

  static void _seams(Canvas canvas, Rect band, Paint stroke) {
    final random = math.Random(31);
    for (var route = 0; route < 4; route++) {
      var point = Offset(
        band.left + band.width * (route + .4) / 4,
        band.bottom,
      );
      final path = Path()..moveTo(point.dx, point.dy);
      for (var i = 0; i < 7; i++) {
        final next = Offset(
          point.dx + (random.nextDouble() - .5) * 72,
          point.dy - band.height / 7,
        );
        path.lineTo(next.dx, next.dy);
        if (i == 2 || i == 4) {
          canvas.drawLine(
            next,
            next + Offset(route.isEven ? 35 : -35, -28),
            stroke,
          );
        }
        point = next;
      }
      canvas.drawPath(path, stroke..strokeWidth = 1.5);
    }
  }

  static void _circuit(Canvas canvas, Rect band, Paint stroke) {
    final gap = band.width / 9;
    for (var i = 0; i < 9; i++) {
      final x = band.left + gap * (i + .5);
      final turn = band.bottom - band.height * (.2 + (i % 4) * .14);
      final end = Offset(x + gap * .45, turn - gap * .45);
      final path = Path()
        ..moveTo(x, band.bottom)
        ..lineTo(x, turn)
        ..lineTo(end.dx, end.dy)
        ..lineTo(end.dx, end.dy - gap * .8);
      canvas.drawPath(path, stroke);
      canvas.drawCircle(end - Offset(0, gap * .8), 3, stroke);
    }
  }

  static void _halftone(Canvas canvas, Rect band, Paint stroke) {
    final fill = Paint()..color = stroke.color;
    // At most a few hundred dots, cached by the backdrop's repaint boundary.
    const step = 18.0;
    for (var y = band.top; y < band.bottom; y += step) {
      for (var x = band.left; x < band.right; x += step) {
        final wave = math.sin(x / 45 + y / 55);
        final radius = .6 + (wave + 1) * 1.35;
        canvas.drawCircle(Offset(x + math.sin(y / 60) * 6, y), radius, fill);
      }
    }
  }

  @override
  bool shouldRepaint(NexTexturePainter old) =>
      old.texture != texture ||
      old.ink != ink ||
      old.extent != extent ||
      old.pixelRatio != pixelRatio;
}

/// Rasterizes a static backdrop once and keeps the image, so a frame that
/// draws it costs one textured quad instead of the whole vector picture.
///
/// A `RepaintBoundary` already keeps a static painter from being re-RECORDED
/// while the page scrolls over it. Recording is not the expensive half,
/// though: under Impeller — Flutter's renderer on Android and iOS — there is
/// no raster cache, so an unchanged picture's commands are re-executed by
/// the GPU on every frame the screen moves, however static the picture is.
/// A theme's bottom-of-screen motif costs ~860 strokes and a full-screen
/// `saveLayer` that way, on each of the 120 frames a second a phone spends
/// on a flick. Rasterizing the picture once into a GPU-resident image and
/// drawing that instead is the documented answer, and it is exactly what a
/// `RepaintBoundary` used to arrange under Skia.
///
/// Images are keyed by everything the caller's picture depends on. The cache
/// is bounded by bytes rather than entries — one motif is a few megabytes,
/// one full-page background pattern rather more, and a picker full of tiny
/// preview swatches is noise — and eviction disposes.
///
/// Returns null where an image cannot be made (an unsupported platform, or
/// anything the engine refuses); callers fall back to painting the picture,
/// which is what they did before.
final _rasterCache = <Object, ui.Image>{};
var _rasterCacheBytes = 0;
const _rasterCacheBudget = 48 * 1024 * 1024;

ui.Image? nexRasterCachedImage({
  required Object key,
  required Size size,
  required double pixelRatio,
  required void Function(ui.Canvas canvas, Size size) paint,
}) {
  final cached = _rasterCache[key];
  if (cached != null) return cached;

  final w = (size.width * pixelRatio).round();
  final h = (size.height * pixelRatio).round();
  if (w <= 0 || h <= 0 || w > 32768 || h > 32768) return null;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.scale(pixelRatio);
  paint(canvas, size);
  final picture = recorder.endRecording();
  try {
    final image = picture.toImageSync(w, h);
    _rasterCache[key] = image;
    _rasterCacheBytes += w * h * 4;
    _evictRasterCache();
    // An image larger than the whole budget is evicted — and disposed — the
    // moment it is made; drawing that handle would throw. Null paints the
    // picture instead, as an uncacheable backdrop always has.
    return _rasterCache[key];
  } on Object {
    return null;
  } finally {
    picture.dispose();
  }
}

void _evictRasterCache() {
  if (_rasterCacheBytes <= _rasterCacheBudget && _rasterCache.length <= 12) {
    return;
  }
  // Oldest-inserted first, which is also the least likely to be the one
  // still on screen.
  final keys = _rasterCache.keys.toList(growable: false);
  for (final key in keys) {
    if (_rasterCacheBytes <= _rasterCacheBudget && _rasterCache.length <= 12) {
      return;
    }
    final image = _rasterCache.remove(key);
    if (image == null) continue;
    _rasterCacheBytes -= image.width * image.height * 4;
    image.dispose();
  }
}
