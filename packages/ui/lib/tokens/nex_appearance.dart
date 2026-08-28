import 'dart:ui';

import 'package:flutter/material.dart';

import 'nex_tokens.dart';

enum NexBackgroundPattern { plain, aurora, ripple, weave }

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
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: visual.glassTint,
              border: Border.all(color: visual.glassBorder),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  visual.glassHighlight,
                  visual.glassTint.withValues(alpha: 0.18),
                ],
                stops: const [0, 0.72],
              ),
            ),
            child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
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

  @override
  bool shouldRepaint(covariant _BackgroundPainter oldDelegate) =>
      pattern != oldDelegate.pattern ||
      brightness != oldDelegate.brightness ||
      accent != oldDelegate.accent;
}
