import 'dart:math' as math;
import 'dart:ui';

// For `listEquals`, which `material.dart` does not re-export: its export of
// `foundation.dart` is a `show` list, and that is not on it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'nex_tokens.dart';

/// The backdrop the whole app sits on.
///
/// Order is the order they are offered in: the quiet ones first, then the
/// ones that are unmistakably a choice. Names are stored, so an entry can be
/// added anywhere but never renamed — see [NexBackgroundPatternWire].
enum NexBackgroundPattern {
  plain,
  aurora,
  ripple,
  weave,
  dots,
  dusk,
  topography,
  prism,
}

extension NexBackgroundPatternWire on NexBackgroundPattern {
  String get wireName => name;

  static NexBackgroundPattern fromWire(String? value) =>
      NexBackgroundPattern.values.firstWhere(
        (pattern) => pattern.name == value,
        orElse: () => NexBackgroundPattern.plain,
      );
}

/// The four films that turn a blurred backdrop into glass.
///
/// A blur on its own is not a material: it leaves the backdrop's own range
/// intact, so a panel over a dark note is dark and the same panel over a pale
/// one is pale, and no tint that is transparent enough to see through can
/// carry text on both. The fix the previous pass reached for was to stop
/// seeing through it at all — a tint at 86% over a sigma-32 blur, which is a
/// painted panel wearing a blur, not glass.
///
/// Apple's own kit does something better, and the structure here is its
/// structure, read out of the iOS 27 UI kit's `Button - Liquid Glass`
/// (`Refraction 70 · Frost 6 · Opacity 25`). Two flat films squeeze the
/// backdrop's range toward the middle, an additive film lifts the floor, and
/// a luminosity film pins the result's brightness while leaving the
/// backdrop's hue alone. What comes out is translucent — a blue note behind
/// the glass really does tint it blue — and yet lands inside a band narrow
/// enough that one text colour reads on all of it.
///
/// Where this departs from the kit is *where* that band sits, and the reason
/// is in `nex_tokens.dart` beside the numbers: Apple's light band is pinned
/// near white, and a panel on a near-white page that comes out near white is
/// a material nobody can see. The band was moved down until a panel reads as
/// a shape lying on the page. In light it now spans rgb 161 to 222 — 5.9:1 to
/// 11.3:1 against the light theme's ink, both better than the numbers it
/// replaced.
@immutable
class NexGlassWash {
  const NexGlassWash({
    required this.films,
    required this.lift,
    required this.anchor,
  });

  /// Painted straight onto the blurred backdrop, in order, source-over.
  ///
  /// One dark and one light, and the order is the point: each one pulls the
  /// backdrop a fixed fraction of the way to its own colour, so together they
  /// compress the range rather than shifting it.
  final List<Color> films;

  /// Added rather than composited — [BlendMode.plus].
  ///
  /// This is what stops a dark backdrop reading as a hole: source-over can
  /// only move the result *toward* a colour, and a film pale enough to lift
  /// black is pale enough to wash out everything else.
  final Color lift;

  /// [BlendMode.luminosity]: the backdrop keeps its hue and saturation and
  /// takes this film's brightness, at this film's alpha.
  ///
  /// The last step, and the one that makes the band narrow enough to put text
  /// on. Doing it with a plain fill instead would drag every backdrop toward
  /// grey and take the tint with it.
  final Color anchor;

  NexGlassWash lerp(NexGlassWash other, double t) => NexGlassWash(
    films: [
      for (var i = 0; i < films.length; i++)
        Color.lerp(films[i], other.films[i], t)!,
    ],
    lift: Color.lerp(lift, other.lift, t)!,
    anchor: Color.lerp(anchor, other.anchor, t)!,
  );

  @override
  bool operator ==(Object other) =>
      other is NexGlassWash &&
      listEquals(other.films, films) &&
      other.lift == lift &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(Object.hashAll(films), lift, anchor);
}

@immutable
class NexVisualStyle extends ThemeExtension<NexVisualStyle> {
  const NexVisualStyle({
    required this.liquidGlass,
    required this.baseColor,
    required this.glassWash,
    required this.glassOpaque,
    required this.glassRim,
    required this.glassBorder,
    required this.glassShadow,
    required this.blurSigma,
  });

  final bool liquidGlass;
  final Color baseColor;

  /// What the blurred backdrop is turned into — see [NexGlassWash].
  final NexGlassWash glassWash;

  /// What a glass surface falls back to when the backdrop must not show
  /// through: high contrast, and the non-glass appearance's sheets.
  final Color glassOpaque;

  /// The bright sliver down the left and right edges.
  ///
  /// Apple's kit draws it as two zero-blur shadows offset ±1.25 and pulled
  /// back 0.75, which leaves half a pixel showing on each side and nothing at
  /// the top or bottom. That asymmetry is most of what reads as a curved edge
  /// catching the light, and a border drawn evenly all the way round cannot
  /// say it — see the light angle of 0 in the kit's variables.
  final Color glassRim;

  /// The hairline around the whole shape, under the rim.
  final Color glassBorder;

  /// The drop shadow, which is very nearly nothing: Apple's is black at 2%,
  /// 8 down, 15 of blur. A heavy one is what made the old panels read as
  /// cards that had been blurred rather than as glass lying on the page.
  final Color glassShadow;

  final double blurSigma;

  @override
  NexVisualStyle copyWith({
    bool? liquidGlass,
    Color? baseColor,
    NexGlassWash? glassWash,
    Color? glassOpaque,
    Color? glassRim,
    Color? glassBorder,
    Color? glassShadow,
    double? blurSigma,
  }) => NexVisualStyle(
    liquidGlass: liquidGlass ?? this.liquidGlass,
    baseColor: baseColor ?? this.baseColor,
    glassWash: glassWash ?? this.glassWash,
    glassOpaque: glassOpaque ?? this.glassOpaque,
    glassRim: glassRim ?? this.glassRim,
    glassBorder: glassBorder ?? this.glassBorder,
    glassShadow: glassShadow ?? this.glassShadow,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  NexVisualStyle lerp(covariant NexVisualStyle? other, double t) {
    if (other == null) return this;
    return NexVisualStyle(
      liquidGlass: t < 0.5 ? liquidGlass : other.liquidGlass,
      baseColor: Color.lerp(baseColor, other.baseColor, t)!,
      glassWash: glassWash.lerp(other.glassWash, t),
      glassOpaque: Color.lerp(glassOpaque, other.glassOpaque, t)!,
      glassRim: Color.lerp(glassRim, other.glassRim, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
    );
  }

  /// The four shadows every glass shape carries: the two rim slivers, the
  /// hairline, and the drop.
  ///
  /// All four sit *outside* the shape, which is why they live here and not in
  /// the decoration the blur is clipped to — a border painted inside the clip
  /// would be blurred along with everything behind it.
  List<BoxShadow> get glassEdge => [
    BoxShadow(color: glassBorder, spreadRadius: 0.5),
    BoxShadow(
      color: glassRim,
      offset: const Offset(1.25, 0),
      spreadRadius: -0.75,
    ),
    BoxShadow(
      color: glassRim,
      offset: const Offset(-1.25, 0),
      spreadRadius: -0.75,
    ),
    BoxShadow(color: glassShadow, offset: const Offset(0, 8), blurRadius: 15),
  ];
}

extension NexVisualStyleContext on BuildContext {
  NexVisualStyle get nexVisualStyle {
    final theme = Theme.of(this);
    return theme.extension<NexVisualStyle>() ??
        NexVisualStyle(
          liquidGlass: false,
          baseColor: theme.scaffoldBackgroundColor,
          glassWash: const NexGlassWash(
            films: [Colors.transparent, Colors.transparent],
            lift: Colors.transparent,
            anchor: Colors.transparent,
          ),
          glassOpaque: theme.colorScheme.surfaceContainerLowest,
          glassRim: Colors.transparent,
          glassBorder: theme.colorScheme.outlineVariant,
          glassShadow: Colors.transparent,
          blurSigma: 0,
        );
  }
}

class NexAppBackground extends StatelessWidget {
  const NexAppBackground({
    super.key,
    required this.pattern,
    required this.child,
  });

  final NexBackgroundPattern pattern;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.nexVisualStyle.baseColor;
    if (pattern == NexBackgroundPattern.plain) {
      return ColoredBox(color: base, child: child);
    }
    return ColoredBox(
      color: base,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _BackgroundPainter(
                pattern: pattern,
                brightness: theme.brightness,
                accent: theme.colorScheme.primary,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class NexGlassSurface extends StatelessWidget {
  const NexGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(NexRadius.xl)),
    this.padding,
    this.fallbackColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// What to draw outside the glass appearance.
  ///
  /// Null keeps the old behaviour — nothing at all, for a caller that is
  /// already sitting on a surface of its own and only wanted the blur when
  /// there was one. Anything that floats over the page has to pass a colour,
  /// or it is text on whatever line of somebody's note happens to be behind
  /// it for every reader who has glass switched off.
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final visual = context.nexVisualStyle;
    if (!visual.liquidGlass) {
      final ground = fallbackColor;
      final body = Padding(padding: padding ?? EdgeInsets.zero, child: child);
      if (ground == null) return body;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: ground,
          borderRadius: borderRadius,
          border: Border.all(color: visual.glassBorder),
        ),
        child: body,
      );
    }
    if (MediaQuery.highContrastOf(context)) {
      final opaqueSurface = Color.alphaBlend(
        visual.glassOpaque,
        visual.baseColor,
      ).withValues(alpha: 1);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: opaqueSurface,
          borderRadius: borderRadius,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      );
    }
    return CustomPaint(
      painter: _GlassEdgePainter(
        shadows: visual.glassEdge,
        borderRadius: borderRadius,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: visual.blurSigma,
            sigmaY: visual.blurSigma,
          ),
          // Inside the filter, so the films blend against the blurred
          // backdrop rather than against nothing — which is the whole
          // arrangement. [BlendMode.plus] and [BlendMode.luminosity] read
          // what has already been painted, and what has already been painted
          // here is the page, blurred.
          child: CustomPaint(
            painter: _GlassWashPainter(visual.glassWash),
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
          ),
        ),
      ),
    );
  }
}

/// The blurred band behind a top bar, for a bar the content scrolls under.
///
/// [NexGlassSurface] is the wrong shape for this: it is a rounded panel with a
/// shadow and a border all the way round, which is right for a card floating
/// over a page and wrong for a strip welded to the top edge of one. This is
/// the same material — the same blur and the same four films — squared off,
/// with no rim and a hairline only along the bottom, where the bar actually
/// meets the list. A bar runs off both sides of the screen, so it has no left
/// or right edge for a rim to catch.
///
/// Meant for an `AppBar`'s `flexibleSpace`, and only worth anything if that
/// bar's own `backgroundColor` is transparent and the body extends behind it.
/// A `BackdropFilter` blurs whatever has already been painted beneath it, so a
/// bar that fills itself in first has nothing left to blur but its own fill,
/// and a body that stops at the bar's bottom edge gives it nothing to blur at
/// all — which is how a translucent bar ends up looking like a dimmed pane of
/// glass rather than a frosted one.
///
/// Nothing at all outside the glass appearance: there the bar is opaque, and
/// its own colour is the right one to paint it with.
class NexGlassBar extends StatelessWidget {
  const NexGlassBar({super.key});

  @override
  Widget build(BuildContext context) {
    final visual = context.nexVisualStyle;
    if (!visual.liquidGlass) return const SizedBox.shrink();
    // Reading what is behind a bar is the point of the effect and the enemy of
    // this setting, so it stops being translucent rather than being blurred
    // harder — the same trade [NexGlassSurface] makes.
    if (MediaQuery.highContrastOf(context)) {
      return ColoredBox(
        color: Color.alphaBlend(
          visual.glassOpaque,
          visual.baseColor,
        ).withValues(alpha: 1),
      );
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: visual.blurSigma,
          sigmaY: visual.blurSigma,
        ),
        child: CustomPaint(
          painter: _GlassWashPainter(visual.glassWash),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: visual.glassBorder)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a glass shape's edge, and only the part of it that falls outside
/// the shape.
///
/// That clip is the whole reason this exists rather than a `boxShadow` on a
/// [BoxDecoration]. Flutter paints a box shadow as a *filled* shape behind
/// the box — under an opaque fill nobody can tell, but glass is not opaque,
/// and four filled shapes showing through it put every pane on a grey plate
/// of its own making. Worse, the blur reads them too, so the backdrop a pane
/// is supposed to show is its own shadow. CSS clips outer shadows to outside
/// the border box; `BoxDecoration` does not, so this does.
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({required this.shadows, required this.borderRadius});

  final List<BoxShadow> shadows;
  final BorderRadius borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = borderRadius.toRRect(Offset.zero & size);
    // How far outside the shape a shadow can reach, so the clip's outer
    // rectangle is big enough to hold all of them. Blur is doubled because a
    // Gaussian carries visibly past its radius.
    var reach = 1.0;
    for (final shadow in shadows) {
      reach = math.max(
        reach,
        shadow.offset.distance + shadow.spreadRadius + shadow.blurRadius * 2,
      );
    }
    // Everything except the shape itself, as an even-odd path. `clipRRect`
    // takes no `clipOp` — only `clipRect` does — so subtracting a rounded
    // rectangle has to be said this way.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(reach + 1))
      ..addRRect(shape);
    canvas.save();
    canvas.clipPath(outside);
    for (final shadow in shadows) {
      if (shadow.color.a == 0) continue;
      canvas.drawRRect(
        shape.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      !listEquals(oldDelegate.shadows, shadows);
}

/// Lays [NexGlassWash]'s four films over whatever the canvas already holds.
///
/// Deliberately no `saveLayer`. Two of the four blend against the
/// destination, and a fresh layer starts empty, so wrapping these calls would
/// have them blend against transparent black and produce a flat grey slab —
/// the failure mode that looks like the effect working until you put it over
/// something coloured.
class _GlassWashPainter extends CustomPainter {
  const _GlassWashPainter(this.wash);

  final NexGlassWash wash;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    for (final film in wash.films) {
      canvas.drawRect(area, Paint()..color = film);
    }
    canvas.drawRect(
      area,
      Paint()
        ..color = wash.lift
        ..blendMode = BlendMode.plus,
    );
    canvas.drawRect(
      area,
      Paint()
        ..color = wash.anchor
        ..blendMode = BlendMode.luminosity,
    );
  }

  @override
  bool shouldRepaint(_GlassWashPainter oldDelegate) => oldDelegate.wash != wash;
}

class NexBackgroundPreview extends StatelessWidget {
  const NexBackgroundPreview({super.key, required this.pattern});

  final NexBackgroundPattern pattern;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(NexRadius.md),
    child: SizedBox(
      width: 46,
      height: 40,
      child: NexAppBackground(
        pattern: pattern,
        child: Center(
          child: Container(
            width: 23,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerLowest.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter({
    required this.pattern,
    required this.brightness,
    required this.accent,
  });

  final NexBackgroundPattern pattern;
  final Brightness brightness;
  final Color accent;

  bool get _dark => brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pattern) {
      case NexBackgroundPattern.plain:
        return;
      case NexBackgroundPattern.aurora:
        _paintAurora(canvas, size);
        return;
      case NexBackgroundPattern.ripple:
        _paintRipple(canvas, size);
        return;
      case NexBackgroundPattern.weave:
        _paintWeave(canvas, size);
        return;
      case NexBackgroundPattern.dots:
        _paintDots(canvas, size);
        return;
      case NexBackgroundPattern.dusk:
        _paintDusk(canvas, size);
        return;
      case NexBackgroundPattern.topography:
        _paintTopography(canvas, size);
        return;
      case NexBackgroundPattern.prism:
        _paintPrism(canvas, size);
        return;
    }
  }

  void _paintAurora(Canvas canvas, Size size) {
    final alpha = _dark ? 0.18 : 0.11;
    final radius = size.longestSide * 0.62;
    final blooms = [
      (Offset(size.width * 0.08, size.height * 0.10), accent),
      (Offset(size.width * 0.92, size.height * 0.42), const Color(0xFF8B5CF6)),
      (Offset(size.width * 0.25, size.height * 0.92), const Color(0xFF14B8A6)),
    ];
    for (final bloom in blooms) {
      canvas.drawCircle(
        bloom.$1,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              bloom.$2.withValues(alpha: alpha),
              bloom.$2.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: bloom.$1, radius: radius)),
      );
    }
  }

  void _paintRipple(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = accent.withValues(alpha: _dark ? 0.10 : 0.08);
    final center = Offset(size.width * 0.78, size.height * 0.18);
    for (var radius = 36.0; radius < size.longestSide; radius += 44) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  void _paintWeave(Canvas canvas, Size size) {
    const step = 28.0;
    final paint = Paint()
      ..strokeWidth = 0.75
      ..color = (_dark ? Colors.white : Colors.black).withValues(alpha: 0.045);
    for (var offset = -size.height; offset < size.width; offset += step) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(offset + size.height, 0),
        Offset(offset, size.height),
        paint,
      );
    }
  }

  /// Graph paper, at the density of a notebook rather than a spreadsheet.
  ///
  /// The quietest thing that is still visibly *something*: a grid of dots
  /// carries no direction and no focal point, so nothing on top of it has to
  /// compete with it. 26 apart is far enough that a line of text crosses only
  /// a handful.
  void _paintDots(Canvas canvas, Size size) {
    const step = 26.0;
    final paint = Paint()
      ..color = (_dark ? Colors.white : Colors.black).withValues(alpha: 0.06);
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  /// One wash of accent rising off the bottom edge.
  ///
  /// Aurora with a single bloom and no colours of its own — the timeline
  /// starts at the top and ends here, so the only tinted part of the screen
  /// is the part with the least on it.
  void _paintDusk(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, size.height * 0.45, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            accent.withValues(alpha: _dark ? 0.20 : 0.13),
            accent.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }

  /// Contour lines, the way a map draws a hill.
  ///
  /// Deliberately not concentric circles — [_paintRipple] already is one, and
  /// what makes a contour read as terrain is that no two rings are the same
  /// shape. Each ring is a circle whose radius is bent by a fixed pair of
  /// sines, so the drawing is elaborate and entirely deterministic: no seed,
  /// no stored state, and the same picture on every repaint.
  void _paintTopography(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: _dark ? 0.13 : 0.10);
    final center = Offset(size.width * 0.62, size.height * 0.34);
    const steps = 72;
    for (var ring = 0; ring < 11; ring++) {
      final base = 40.0 + ring * 46;
      final path = Path();
      for (var i = 0; i <= steps; i++) {
        final angle = i / steps * 2 * math.pi;
        // Two waves at different frequencies, drifting per ring, so the
        // rings nest without ever running parallel.
        final wobble =
            math.sin(angle * 3 + ring * 0.6) * (10 + ring * 2.2) +
            math.sin(angle * 5 - ring * 0.35) * 6;
        final radius = base + wobble;
        final point = Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius * 0.82,
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  /// Wide diagonal bands of colour, edges dissolved into each other.
  ///
  /// The loudest of the set and the only one that does not take its colour
  /// from the accent: the point of it is the spread between the bands, which
  /// a single hue cannot produce. Still built from gradients that reach zero
  /// at both ends, so it is a tint across the screen rather than stripes on
  /// it — text sits on top of it as readably as on any of the others.
  void _paintPrism(Canvas canvas, Size size) {
    final alpha = _dark ? 0.22 : 0.15;
    final bands = <(Color, double)>[
      (accent, -0.15),
      (const Color(0xFFEC4899), 0.18),
      (const Color(0xFFF59E0B), 0.52),
      (const Color(0xFF10B981), 0.86),
    ];
    // Rotated about the centre so the bands run corner to corner whatever
    // the screen's proportions are.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 5);
    canvas.translate(-size.width / 2, -size.height / 2);
    final span = size.longestSide * 1.6;
    final width = span / 2.6;
    for (final band in bands) {
      final left = -size.width * 0.3 + band.$2 * span;
      final rect = Rect.fromLTWH(left, -span * 0.3, width, span * 1.6);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              band.$1.withValues(alpha: 0),
              band.$1.withValues(alpha: alpha),
              band.$1.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      pattern != oldDelegate.pattern ||
      brightness != oldDelegate.brightness ||
      accent != oldDelegate.accent;
}
