import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// A light that travels around a shape's border.
///
/// Meant for the two surfaces where a model is doing something: the brief at
/// the top of the timeline, and the box the assistant is typed into. It says
/// "this is generated" without a badge, a sparkle or a word — which is the
/// same reason the brief lost its heading.
///
/// Written here rather than pulled in: the effect was asked for as a React
/// package, and there is no React in this app. What a package like that does
/// is a rotating sweep gradient stroked along a rounded rectangle, which is
/// forty lines of `CustomPainter` and no dependency.
///
/// It does not run forever. A light going round and round in the corner of a
/// notes app is a battery cost with no reader — and, less obviously, an
/// animation that never ends means `pumpAndSettle` never settles, so every
/// test that so much as opens a screen carrying one hangs. Both of those are
/// the same fact about perpetual motion: nothing is being marked.
///
/// So it runs [laps] times and rests, and plays again when [token] changes —
/// which is what actually happens: a request starts, an answer lands. The
/// controller is stopped rather than hidden when [active] is false, and the
/// beam stands still when the platform asks for reduced motion.
class NexBorderBeam extends StatefulWidget {
  const NexBorderBeam({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(NexRadius.lg)),
    this.colors = nexAssistantSpectrum,
    this.thickness = 1.5,
    this.strength = 0.7,
    this.active = true,
    this.laps = 4,
    this.token,
    this.period = const Duration(milliseconds: 2200),
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// The sweep, first colour repeated last so the loop has no seam.
  final List<Color> colors;

  /// How wide the lit line is. The glow around it is derived from this.
  final double thickness;

  /// 0–1. Scales the glow's spread and its opacity together, because those
  /// are the two things that read as one quantity: how brightly it is lit.
  final double strength;

  /// False stops the animation and leaves the border unpainted.
  final bool active;

  /// How many times round before it rests.
  final int laps;

  /// Changing this plays the laps again.
  ///
  /// Whatever the light is marking: the brief's text, so a new one lights up
  /// and the same one does not keep asking to be looked at.
  final Object? token;

  /// How long one lap takes. Unhurried on purpose: this sits beside text
  /// somebody is reading, and anything quick enough to notice is quick enough
  /// to compete with the words.
  final Duration period;

  @override
  State<NexBorderBeam> createState() => _NexBorderBeamState();
}

class _NexBorderBeamState extends State<NexBorderBeam>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lap = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  /// Whether the lap should be running: something to show, and a platform
  /// that has not asked for stillness.
  bool _shouldRun(BuildContext context) =>
      widget.active && !MediaQuery.disableAnimationsOf(context);

  void _play(BuildContext context) {
    if (!_shouldRun(context)) {
      if (_lap.isAnimating) _lap.stop();
      return;
    }
    if (!_lap.isAnimating) _lap.repeat(count: widget.laps);
  }

  /// Back to the start and round again, for a [NexBorderBeam.token] that has
  /// changed while the last run was still going.
  void _replay(BuildContext context) {
    _lap.stop();
    _lap.value = 0;
    _play(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _play(context);
  }

  @override
  void didUpdateWidget(NexBorderBeam old) {
    super.didUpdateWidget(old);
    if (widget.period != old.period) _lap.duration = widget.period;
    if (widget.token != old.token || (widget.active && !old.active)) {
      _replay(context);
    } else {
      _play(context);
    }
  }

  @override
  void dispose() {
    _lap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    // Its own layer: this repaints on every frame of the lap, and without a
    // boundary it would drag whatever list it is sitting in along with it.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _lap,
        builder: (context, child) => CustomPaint(
          foregroundPainter: _BeamPainter(
            turn: _lap.value,
            borderRadius: widget.borderRadius,
            colors: widget.colors,
            thickness: widget.thickness,
            strength: widget.strength.clamp(0.0, 1.0),
          ),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({
    required this.turn,
    required this.borderRadius,
    required this.colors,
    required this.thickness,
    required this.strength,
  });

  final double turn;
  final BorderRadius borderRadius;
  final List<Color> colors;
  final double thickness;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final area = Offset.zero & size;
    // Inset by half the stroke, so the line sits *on* the edge rather than
    // straddling it and being clipped in half by whatever is above.
    final shape = borderRadius.toRRect(area).deflate(thickness / 2);

    Shader sweep(double alpha) => SweepGradient(
      colors: [
        for (final c in colors) c.withValues(alpha: c.a * alpha),
      ],
      transform: GradientRotation(turn * 2 * math.pi),
    ).createShader(area);

    // The glow first, wide and soft, then the line over it. Drawn as two
    // strokes rather than one blurred one: a blur alone has no core, and a
    // core alone has no light.
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = sweep(0.55 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness + 6 * strength
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 5 * strength),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = sweep(0.35 + 0.65 * strength)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.turn != turn ||
      old.strength != strength ||
      old.thickness != thickness ||
      old.borderRadius != borderRadius ||
      !listEquals(old.colors, colors);
}
