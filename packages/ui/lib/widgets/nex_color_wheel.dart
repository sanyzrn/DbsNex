import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/nex_tokens.dart';

/// A hue-and-saturation disc, dragged with one finger.
///
/// Replaces a stack of three sliders. The sliders were correct and nobody
/// could use them: picking a colour is not three independent decisions, it is
/// one — you know the colour you want before you know its hue angle, and
/// finding it meant moving one slider, seeing the answer change, and moving
/// the next. The disc is the same HSV space laid out so the whole of it is
/// visible at once and any point in it is one gesture away.
///
/// Hue is the angle and saturation is the distance from the centre, which is
/// why the middle is white and the rim is fully saturated. Brightness is the
/// one axis a flat disc has nowhere to put, so it stays a slider — see
/// [NexBrightnessSlider].
class NexColorWheel extends StatelessWidget {
  const NexColorWheel({
    super.key,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
    this.diameter = 240,
    this.semanticLabel,
  });

  /// Degrees, 0-360.
  final double hue;

  /// 0-1, centre to rim.
  final double saturation;

  /// 0-1. Darkens the whole disc, so what is under the thumb is what the
  /// colour will actually be rather than a bright version of its hue.
  final double value;

  /// Fires with the new hue and saturation for a touch anywhere on the disc.
  final void Function(double hue, double saturation) onChanged;

  final double diameter;

  /// Announced in place of the disc, which a screen reader has nothing else
  /// to say about.
  final String? semanticLabel;

  void _handle(Offset local) {
    final radius = diameter / 2;
    final dx = local.dx - radius;
    final dy = local.dy - radius;
    final distance = math.sqrt(dx * dx + dy * dy);
    // Clamped rather than ignored: a drag that runs off the edge should pin
    // to the rim and keep tracking, not stop dead the moment it leaves.
    final nextSaturation = (distance / radius).clamp(0.0, 1.0);
    // atan2 measures from the positive x-axis counter-clockwise; the painter
    // sweeps clockwise from the top, so the same +90 offset applies to both
    // and the thumb lands on the colour under the finger.
    var angle = math.atan2(dy, dx) * 180 / math.pi + 90;
    if (angle < 0) angle += 360;
    onChanged(angle % 360, nextSaturation);
  }

  @override
  Widget build(BuildContext context) {
    final radius = diameter / 2;
    final radians = (hue - 90) * math.pi / 180;
    final thumb = Offset(
      radius + math.cos(radians) * saturation * radius,
      radius + math.sin(radians) * saturation * radius,
    );
    final selected = HSVColor.fromAHSV(1, hue, saturation, value).toColor();
    return Semantics(
      slider: true,
      label: semanticLabel,
      child: GestureDetector(
        // Tap *and* drag, not one recognizer covering both. A pan does not
        // claim the gesture until the finger has moved past the slop
        // distance, so on `onPanDown` alone a plain tap on a colour did
        // nothing at all — the one gesture someone tries first.
        //
        // A Listener would fire immediately and was the wrong fix: it never
        // enters the gesture arena, so a vertical drag across the disc would
        // scroll the sheet underneath at the same time as picking a colour.
        onTapDown: (details) => _handle(details.localPosition),
        onPanStart: (details) => _handle(details.localPosition),
        onPanUpdate: (details) => _handle(details.localPosition),
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Its own layer: the disc is a pair of gradients that never
              // change while a finger is down, and only the thumb moves.
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(diameter),
                  painter: _WheelPainter(value: value),
                ),
              ),
              Positioned(
                left: thumb.dx - 14,
                top: thumb.dy - 14,
                child: _Thumb(color: selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        // White, not the theme's outline: the ring sits on top of every hue
        // there is, so it cannot be a colour that only contrasts with some
        // of them. The shadow is what keeps it visible over the white centre.
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
    ),
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.value});

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Hue: a full turn of the spectrum. Starting at -90° puts red at the top,
    // which is where every colour wheel people have already used puts it.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          transform: const GradientRotation(-math.pi / 2),
          colors: [
            for (var i = 0; i <= 360; i += 30)
              HSVColor.fromAHSV(1, i % 360, 1, 1).toColor(),
          ],
        ).createShader(rect),
    );

    // Saturation: white in the middle fading out to nothing at the rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: const [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );

    // Brightness, as a black veil over the whole disc. Without it the wheel
    // stays bright while the slider says otherwise, and the thumb sits on a
    // colour that is not the one being chosen.
    if (value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - value),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      value != oldDelegate.value;
}

/// The one axis the disc has nowhere to put: black through the colour itself.
class NexBrightnessSlider extends StatelessWidget {
  const NexBrightnessSlider({
    super.key,
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              // Directional, not physical. `Slider` runs start-to-end, so in
              // a right-to-left layout its zero is on the right — while a
              // plain LinearGradient always paints left to right. The two ran
              // opposite ways in Persian, so dragging toward black gave
              // white.
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  Colors.black,
                  HSVColor.fromAHSV(1, hue, saturation, 1).toColor(),
                ],
              ),
              border: Border.all(color: theme.colorScheme.outline),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 12,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
        ),
      ],
    );
  }
}

/// One round colour, as a tap target of at least [nexMinTapTarget].
///
/// The dot is 30 and the box around it is the full minimum, so a row of these
/// reads as swatches and behaves as buttons.
class NexColorSwatch extends StatelessWidget {
  const NexColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.semanticLabel,
  });

  /// Null paints the surface instead — the "no colour" case, which is a real
  /// choice for a tag and not the same as an unset one.
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  /// Drawn inside the dot. Carries the meaning a colourless swatch cannot.
  final IconData? icon;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: nexMinTapTarget,
          height: nexMinTapTarget,
          child: Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color ?? theme.colorScheme.surface,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline,
                  width: selected ? 3 : 1,
                ),
              ),
              child: icon == null
                  ? null
                  : Icon(icon, size: 14, color: theme.colorScheme.secondary),
            ),
          ),
        ),
      ),
    );
  }
}
