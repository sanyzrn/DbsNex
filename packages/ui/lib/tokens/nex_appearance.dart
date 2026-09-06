import 'dart:math' as math;
import 'dart:ui';

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

@immutable
class NexVisualStyle extends ThemeExtension<NexVisualStyle> {
  const NexVisualStyle({
    required this.liquidGlass,
    required this.baseColor,
    required this.glassTint,
    required this.glassBorder,
    required this.glassHighlight,
    required this.glassShadow,
    required this.blurSigma,
  });

  final bool liquidGlass;
  final Color baseColor;
  final Color glassTint;
  final Color glassBorder;
  final Color glassHighlight;
  final Color glassShadow;
  final double blurSigma;

  @override
  NexVisualStyle copyWith({
    bool? liquidGlass,
    Color? baseColor,
    Color? glassTint,
    Color? glassBorder,
    Color? glassHighlight,
    Color? glassShadow,
    double? blurSigma,
  }) => NexVisualStyle(
    liquidGlass: liquidGlass ?? this.liquidGlass,
    baseColor: baseColor ?? this.baseColor,
    glassTint: glassTint ?? this.glassTint,
    glassBorder: glassBorder ?? this.glassBorder,
    glassHighlight: glassHighlight ?? this.glassHighlight,
    glassShadow: glassShadow ?? this.glassShadow,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  NexVisualStyle lerp(covariant NexVisualStyle? other, double t) {
    if (other == null) return this;
    return NexVisualStyle(
      liquidGlass: t < 0.5 ? liquidGlass : other.liquidGlass,
      baseColor: Color.lerp(baseColor, other.baseColor, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassHighlight: Color.lerp(glassHighlight, other.glassHighlight, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
    );
  }
}

extension NexVisualStyleContext on BuildContext {
  NexVisualStyle get nexVisualStyle {
    final theme = Theme.of(this);
    return theme.extension<NexVisualStyle>() ??
        NexVisualStyle(
          liquidGlass: false,
          baseColor: theme.scaffoldBackgroundColor,
          glassTint: theme.colorScheme.surfaceContainerLowest,
          glassBorder: theme.colorScheme.outlineVariant,
          glassHighlight: Colors.transparent,
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
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final visual = context.nexVisualStyle;
    if (!visual.liquidGlass) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: child);
    }
    if (MediaQuery.highContrastOf(context)) {
      final opaqueSurface = Color.alphaBlend(
        Theme.of(context).colorScheme.surfaceContainerLowest,
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
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: visual.glassShadow,
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: visual.blurSigma,
            sigmaY: visual.blurSigma,
          ),
          child: DecoratedBox(
            // A flat tint over a heavy blur, and a hairline. No gradient:
            // the diagonal sheen this used to carry lightened one corner of
            // every panel and darkened the other, so a line of text changed
            // contrast depending on where it fell. A system material is even
            // — the depth is in the blur behind it, not in a highlight
            // painted across the front.
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: visual.glassTint,
              border: Border.all(color: visual.glassBorder),
            ),
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
/// the same material — heavy blur, flat tint, hairline — squared off, with the
/// hairline only along the bottom, where the bar actually meets the list.
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
    final scheme = Theme.of(context).colorScheme;
    // Reading what is behind a bar is the point of the effect and the enemy of
    // this setting, so it stops being translucent rather than being blurred
    // harder — the same trade [NexGlassSurface] makes.
    if (MediaQuery.highContrastOf(context)) {
      return ColoredBox(
        color: Color.alphaBlend(
          scheme.surfaceContainerLowest,
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: visual.glassTint,
            border: Border(bottom: BorderSide(color: visual.glassBorder)),
          ),
        ),
      ),
    );
  }
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
